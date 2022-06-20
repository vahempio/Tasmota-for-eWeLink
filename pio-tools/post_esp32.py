# From: https://github.com/letscontrolit/ESPEasy/blob/mega/tools/pio/post_esp32.py
# Thanks TD-er :)

# Combines separate bin files with their respective offsets into a single file
# This single file must then be flashed to an ESP32 node with 0 offset.
#
# Original implementation: Bartłomiej Zimoń (@uzi18)
#
# Special thanks to @Jason2866 for helping debug flashing to >4MB flash
# Thanks @jesserockz (esphome) for adapting to use esptool.py with merge_bin
#
# Typical layout of the generated file:
#    Offset | File
# -  0x1000 | ~\.platformio\packages\framework-arduinoespressif32\tools\sdk\esp32\bin\bootloader_dout_40m.bin
# -  0x8000 | ~\Tasmota\.pio\build\<env name>\partitions.bin
# -  0xe000 | ~\.platformio\packages\framework-arduinoespressif32\tools\partitions\boot_app0.bin
# - 0x10000 | ~\.platformio/packages/framework-arduinoespressif32/variants/tasmota/\<env name>-safeboot.bin
# - 0xe0000 | ~\Tasmota\.pio\build\<env name>/firmware.bin
# - 0x3b0000| ~\Tasmota\.pio\build\<env name>/littlefs.bin

Import("env")

env = DefaultEnvironment()
platform = env.PioPlatform()

from genericpath import exists
import os
import sys
from os.path import join
import csv
import requests
import shutil
import subprocess

sys.path.append(join(platform.get_package_dir("tool-esptoolpy")))
import esptool

FRAMEWORK_DIR = platform.get_package_dir("framework-arduinoespressif32")
variants_dir = join(FRAMEWORK_DIR, "variants", "tasmota")

def esp32_create_chip_string(chip):
    tasmota_platform = env.subst("$BUILD_DIR").split(os.path.sep)[-1]
    tasmota_platform = tasmota_platform.split('-')[0]
    if 'tasmota' and chip[3:] not in tasmota_platform: # quick check for a valid name like 'tasmota' + '32c3'
        print('Unexpected naming conventions in this build environment -> Undefined behavior for further build process!!')
    return tasmota_platform

def esp32_build_filesystem(fs_size):
    files = env.GetProjectOption("custom_files_upload").splitlines()
    filesystem_dir = join(env.subst("$BUILD_DIR"),"littlefs_data")
    if not os.path.exists(filesystem_dir):
        os.makedirs(filesystem_dir)
    print("Creating filesystem with content:")
    for file in files:
        if "no_files" in file:
            continue
        if "http" and "://" in file:
            response = requests.get(file)
            if response.ok:
                target = join(filesystem_dir,file.split(os.path.sep)[-1])
                open(target, "wb").write(response.content)
            else:
                print("Failed to download: ",file)
            continue
        shutil.copy(file, filesystem_dir)
    if not os.listdir(filesystem_dir):
        print("No files added -> will NOT create littlefs.bin and NOT overwrite fs partition!")
        return False
    env.Replace( MKSPIFFSTOOL=platform.get_package_dir("tool-mklittlefs") + '/mklittlefs' )
    tool = env.subst(env["MKSPIFFSTOOL"])
    cmd = (tool,"-c",filesystem_dir,"-s",fs_size,join(env.subst("$BUILD_DIR"),"littlefs.bin"))
    returncode = subprocess.call(cmd, shell=False)
    # print(returncode)
    return True

def esp32_fetch_safeboot_bin(tasmota_platform):
    safeboot_fw_url = "https://github.com/arendst/Tasmota-firmware/raw/main/firmware/tasmota32/" + tasmota_platform + "-safeboot.bin"
    safeboot_fw_name = join(variants_dir, tasmota_platform + "-safeboot.bin")
    if(exists(safeboot_fw_name)):
        print("safeboot binary already in place.")
        return
    print("Will download safeboot binary from URL:")
    print(safeboot_fw_url)
    response = requests.get(safeboot_fw_url)
    open(safeboot_fw_name, "wb").write(response.content)
    print("safeboot binary written to variants dir.")

def esp32_copy_new_safeboot_bin(tasmota_platform,new_local_safeboot_fw):
    print("Copy new local safeboot firmware to variants dir -> using it for further flashing operations")
    safeboot_fw_name = join(variants_dir, tasmota_platform + "-safeboot.bin")
    if os.path.exists(variants_dir):
        shutil.copy(new_local_safeboot_fw, safeboot_fw_name)

def esp32_create_combined_bin(source, target, env):
    #print("Generating combined binary for serial flashing")

    # The offset from begin of the file where the app0 partition starts
    # This is defined in the partition .csv file
    # factory_offset = -1      # error code value - currently unused
    app_offset = 0x10000     # default value for "old" scheme
    fs_offset = -1           # error code value
    with open(env.BoardConfig().get("build.partitions")) as csv_file:
        print("Read partitions from ",env.BoardConfig().get("build.partitions"))
        csv_reader = csv.reader(csv_file, delimiter=',')
        line_count = 0
        for row in csv_reader:
            if line_count == 0:
                print(f'{",  ".join(row)}')
                line_count += 1
            else:
                print(f'{row[0]}   {row[1]}   {row[2]}   {row[3]}   {row[4]}')
                line_count += 1
                if(row[0] == 'app0'):
                    app_offset = int(row[3],base=16)
                # elif(row[0] == 'factory'):
                #     factory_offset = int(row[3],base=16)
                elif(row[0] == 'spiffs'):
                    if esp32_build_filesystem(row[4]):
                        fs_offset = int(row[3],base=16)


    new_file_name = env.subst("$BUILD_DIR/${PROGNAME}.factory.bin")
    sections = env.subst(env.get("FLASH_EXTRA_IMAGES"))
    firmware_name = env.subst("$BUILD_DIR/${PROGNAME}.bin")
    chip = env.get("BOARD_MCU")
    tasmota_platform = esp32_create_chip_string(chip)
    if not os.path.exists(variants_dir):
        os.makedirs(variants_dir)
    if("safeboot" in firmware_name):
        esp32_copy_new_safeboot_bin(tasmota_platform,firmware_name)
    else:
        esp32_fetch_safeboot_bin(tasmota_platform)
    flash_size = env.BoardConfig().get("upload.flash_size", "4MB")
    cmd = [
        "--chip",
        chip,
        "merge_bin",
        "-o",
        new_file_name,
        "--flash_size",
        flash_size,
    ]

    print("    Offset | File")
    for section in sections:
        sect_adr, sect_file = section.split(" ", 1)
        print(f" -  {sect_adr} | {sect_file}")
        cmd += [sect_adr, sect_file]

    # "main" firmware to app0 - mandatory, except we just built a new safeboot bin locally
    if("safeboot" not in firmware_name):
        print(f" - {hex(app_offset)} | {firmware_name}")
        cmd += [hex(app_offset), firmware_name]

    else:
        print("Upload new safeboot binary only")

    if(fs_offset != -1):
        fs_bin = join(env.subst("$BUILD_DIR"),"littlefs.bin")
        if exists(fs_bin):
            print(f" - {hex(fs_offset)}| {fs_bin}")
            cmd += [hex(fs_offset), fs_bin]
            env.Replace(
            UPLOADERFLAGS=[
            "--chip", chip,
            "--port", '"$UPLOAD_PORT"',
            "--baud", "$UPLOAD_SPEED",
            "--before", "default_reset",
            "--after", "hard_reset",
            "write_flash", "-z",
            "--flash_mode", "${__get_board_flash_mode(__env__)}",
            "--flash_freq", "${__get_board_f_flash(__env__)}",
            "--flash_size", flash_size
            ],
            UPLOADCMD='"$PYTHONEXE" "$UPLOADER" $UPLOADERFLAGS ' + " ".join(cmd[7:])
            )
            print("Will use custom upload command for flashing operation to add file system defined for this build target.")

    # print('Using esptool.py arguments: %s' % ' '.join(cmd))

    esptool.main(cmd)


env.AddPostAction("$BUILD_DIR/${PROGNAME}.bin", esp32_create_combined_bin)
