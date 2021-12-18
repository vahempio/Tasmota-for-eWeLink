/*
  user_config_override.h - user configuration overrides my_user_config.h for Tasmota

  Copyright (C) 2021  Theo Arends

  This program is free software: you can redistribute it and/or modify
  it under the terms of the GNU General Public License as published by
  the Free Software Foundation, either version 3 of the License, or
  (at your option) any later version.

  This program is distributed in the hope that it will be useful,
  but WITHOUT ANY WARRANTY; without even the implied warranty of
  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
  GNU General Public License for more details.

  You should have received a copy of the GNU General Public License
  along with this program.  If not, see <http://www.gnu.org/licenses/>.
*/

#ifndef _USER_CONFIG_OVERRIDE_H_
#define _USER_CONFIG_OVERRIDE_H_

#ifdef FIRMWARE_EWELINK
  #undef  SERIAL_LOG_LEVEL
  #define SERIAL_LOG_LEVEL LOG_LEVEL_NONE

  #define USE_ZIGBEE
  #undef  USE_ZIGBEE_ZNP
  #define USE_ZIGBEE_EZSP
  #define USE_UFILESYS
  #define USE_ZIGBEE_EEPROM // T24C512A
  #define USE_TCP_BRIDGE
  #undef  USE_ZIGBEE_CHANNEL
  #define USE_ZIGBEE_CHANNEL 11 // (11-26)
  
  #define USE_ETHERNET
  #undef  ETH_TYPE
  #define ETH_TYPE 0 // ETH_PHY_LAN8720
  #undef  ETH_CLKMODE
  #define ETH_CLKMODE 3 // ETH_CLOCK_GPIO17_OUT
  #undef  ETH_ADDRESS
  #define ETH_ADDRESS 1 // PHY1
#endif

#endif  // _USER_CONFIG_OVERRIDE_H_
