# Tasmota for ZB-GW03 eWeLink with ZHA
All credits to [thehelpfulidiot](https://thehelpfulidiot.com/) (with the fantastic [blog article](https://thehelpfulidiot.com/a-wired-sonoff-Zigbee-alternative)) and the original [Tasmota](https://github.com/arendst/Tasmota) firmware, many thanks!

The build is based on Tasmota v10.1.0 and support hot/cold reboot. Successfully tested on eWeLink gateway - ZB-GW03-V1.3

You can find the product in many places, including Amazon (already purchased [this one](https://www.amazon.fr/dp/B094JKVLNR)).

## Compatible hardware

ZB-GW03 Zigbee to LAN bridge/gateway based on Espressif ESP32 and a Silicon Labs EFR32MG21 Zigbee radio (CoolKit-Technologies "SM-011 V1.0" module).

* ZB-GW03 eWeLink Ethernet Zigbee Gateway (ZB-GW03-V1.0, ZB-GW03-V1.2, ZB-GW03-V1.3), also sold rebranded as:
  * Eachen eWeLink ZigBee Smart Hub
    * https://ewelink.eachen.cc/product/eachen-ewelink-zigbee-bridge-pro-zbbridge-pro/
    * https://ewelinkcommunity.net/device-lists/zigbee/eachen-zb-gw03/
  * SmartWise Zigbee Bridge Pro
    * https://www.okosabbotthon.hu/smartwise-zigbee-bridge-pro

## Install the dev environment
Install the platformio in CLI with:
```
pip3 install -U platformio
```

## Build
```
platformio run -e tasmota32-EWELINK
```
Firmware will be located at `.pio/build/tasmota32-EWELINK/firmware.bin`

You can use the already built firmware in this git repository `bin/tasmota32-EWELINK_11.1.0.bin` [located here](bin/tasmota32-EWELINK_11.1.0.bin).

## Program
Use any tasmota flasher with the previous bin file. Take a look to the [official documentation](https://tasmota.github.io/docs/Getting-Started/).

## Configure your Zigbee gateway for ZHA
Firstly, set up your Tasmota with the WiFi access point: connect it and open `192.168.4.1` to enter your WiFi credentials.

Secondly, add this template in the console (ETH support):
```
backlog Template {"NAME":"ZB-GW03-V1.3","GPIO":[0,0,3552,0,3584,0,0,0,5793,5792,320,544,5536,0,5600,0,0,0,0,5568,0,0,0,0,0,0,0,0,608,640,32,0,0,0,0,0],"FLAG":0,"BASE":1} ; module 0
```

Then, perform a firmware upgrade with the `bin/ncp-uart-sw-6.7.9_115200.ota` [located here](bin/ncp-uart-nsw_6.7.9_115200.ota) (original [source](https://github.com/arendst/Tasmota/tree/development/tools/fw_SonoffZigbeeBridge_ezsp)).

Now, plug the ethernet and check in `Information` that you have a valid ethernet IP address.

For better stability, desactivate permanently the WiFi with:
```
Wifi 0
backlog rule2 on system#boot do Wifi 0 endon ; rule2 1
```

Remap Zigbee Tx/Rx pin to the TCP interface with:
```
backlog template {"NAME":"ZHA-bridge","GPIO":[0,0,5472,0,5504,0,0,0,5793,5792,320,544,5536,0,5600,0,0,0,0,5568,0,0,0,0,0,0,0,0,608,640,32,0,0,0,0,0],"FLAG":0,"BASE":1} ; module 0
```

And finally start the TCP server:
```
backlog rule1 on system#boot do TCPStart 8888 endon ; rule1 1 ; tcpstart 8888
```

Congrats, your eWeLink Zigbee gateway has been converted to an opensource ZHA bridge!

With Home Assistant, add the `Zigbee Home Automation` integration with the ethrnet IP adress and port number `8888`.

## References

* https://templates.blakadder.com/ewelink_ZB-GW03
* https://templates.blakadder.com/sonoff_ZBBridge.html
* https://github.com/arendst/Tasmota/discussions/12764
* https://github.com/arendst/Tasmota/discussions/14168
* https://github.com/arendst/Tasmota/discussions/11536
* https://github.com/arendst/Tasmota/tree/development/tools/fw_SonoffZigbeeBridge_ezsp
* https://github.com/xsp1989/zigbeeFirmware
* https://github.com/syssi/esphome-zb-gw03
* https://github.com/tube0013/tube_gateways
* [https://github.com/CoolKit-Technologies/DevDocs/blob/master/Zigbee/SM-011应用指导书.md](https://github.com/CoolKit-Technologies/DevDocs/blob/master/Zigbee/SM-011%E5%BA%94%E7%94%A8%E6%8C%87%E5%AF%BC%E4%B9%A6.md)
  * https://github.com/zigpy/zigpy/discussions/586
* [https://community.home-assistant.io/t/zb-gw03-ewelink-ethernet-zigbee-gateway...](https://community.home-assistant.io/t/zb-gw03-ewelink-ethernet-zigbee-gateway-now-hacked-with-tasmota-zbbridge-so-can-be-used-via-mqtt-or-as-a-remote-zigbee-adapter-with-home-assistant-zha/341223)
* https://thehelpfulidiot.com/a-wired-sonoff-zigbee-alternative
* https://thehelpfulidiot.com/update-a-wired-sonoff-zigbee-alternative
* https://thehelpfulidiot.com/update-2-a-wired-sonoff-zigbee-alternative
* https://www.digiblur.com/2020/07/how-to-use-sonoff-zigbee-bridge-with.html
* https://www.digiblur.com/2021/03/zigbee2mqtt-with-sonoff-zigbee-bridge.html
* https://www.digiblur.com/2022/02/convert-sonoff-zigbee-bridge-to-router-repeater.html

