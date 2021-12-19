# Tasmota for eWeLink with ZHA
All credits to [thehelpfulidiot](https://thehelpfulidiot.com/) (with the fantastic [blog article](https://thehelpfulidiot.com/a-wired-sonoff-Zigbee-alternative)) and the original [Tasmota](https://github.com/arendst/Tasmota) firmware, many thanks!

The build is based on Tasmota v10.1.0 and support hot/cold reboot. Successfully tested on eWeLink gateway - ZB-GW03-V1.3

You can find the product in many places, including Amazon (already purchased [this one](https://www.amazon.fr/dp/B094JKVLNR)).

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

You can use the already built firmware in this git repository at `bin/tasmota32-EWELINK.bin`

## Program
Use any tasmota flasher with the previous bin file. Take a look to the [official documentation](https://tasmota.github.io/docs/Getting-Started/).

## Configure your Zigbee gateway for ZHA
Firstly, set up your Tasmota with the WiFi access point: connect it and open `192.168.4.1` to enter your WiFi credentials.

Secondly, add this template in the console (ETH support):
```
backlog Template {"NAME":"ZB-GW03-V1.3","GPIO":[0,0,3552,0,3584,0,0,0,5793,5792,320,544,5536,0,5600,0,0,0,0,5568,0,0,0,0,0,0,0,0,608,640,32,0,0,0,0,0],"FLAG":0,"BASE":1} ; module 0
```

Then, perform a firmware upgrade with the `bin/ncp-uart-sw-6.7.9_115200.ota` (original [source](https://github.com/arendst/Tasmota/tree/development/tools/fw_SonoffZigbeeBridge_ezsp)).

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
