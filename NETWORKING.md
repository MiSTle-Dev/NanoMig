# Networking with the NanoMig 1200

Please read [Networking](https://github.com/MiSTle-Dev/FPGA-Companion/tree/main/NETWORKING.md) first!  

To use the Internet with the NanoMig a **Pi-Pico W** or **Pi-Pico2 W** is required as MCU.

The Amiga talks to the Companion over its parallel port (PLIP).  
The Companion joins your WiFi, and your router does the NAT. 

**Example addresses:**  
Router `192.168.0.254`  
Companion `192.168.0.33` (static or dhcp)   
Amiga `192.168.0.66`  

The Amiga's address must be unused in your LAN.

### 1. Connect the Companion to your network by editing config.ini on the SD-Card

```
; network settings
[NETWORK]
MODE=manual          ; manual or dhcp
IP=192.168.0.33
MASK=255.255.255.0
GW=192.168.0.254
DNS=1.1.1.1          ; name server, only with MODE=manual

[NTP]
;IP=192.53.103.108,192.53.103.104,192.53.103.103
;TIMEZONE=+1         ; UTC+1

[WIFI]
SSID=MyWiFi
PASS=MyPassword

[PLIP]
ENABLE=1
PEER=192.168.0.66    ; the Amiga's address, unused in your LAN
```

### 2. Download and install Roadshow 

The demo version is fully functional but has a time limit.

edit **DEVS:Internet/routes** in TextEdit 

```
DEFAULT 192.168.0.254
```

edit **DEVS:Internet/name_resolution** in TextEdit 

```
NAMESERVER 1.1.1.1
```

### 3. Amiga: Plipbox

download and unzip **plipbox-0.6.zip**  

copy **plipbox.device_RELEASE_020** to **Workbench:Devs/Networks**  
rename it to **plipbox.device**

copy **plipbox** from **Storage/NetInterfaces** to **Devs/NetInterfaces**  
open **plipbox** in TextEdit

```
device=plipbox.device
address=192.168.0.66
netmask=255.255.255.0
#configure=dhcp
```

- **address** must equal **PEER** in **config.ini**.  
- Do not use **configure=dhcp**, **#** comments it out

reboot the Amiga!

### 4. Ping

From the Amiga shell, in this order:

```
ping 192.168.0.33     ; the Companion
ping 192.168.0.254    ; your router
ping 1.1.1.1          ; the internet
```

If the first ping works and the others fail, check the gateway entry.  
From a PC, **ping 192.168.0.66** reaches the Amiga and **ping 192.168.0.33** the Companion

### 5. FTP and Telnet to the Companion

Use the Companion's LAN address **`192.168.0.33**.  
Both work from the Amiga over PLIP and from a PC on the LAN.  

**FTP** (port 21) gives access to the Companion's SD card.  
Any user name and password are accepted. Passive mode only:  
  ```
  ftp 192.168.0.33
  ```
**Telnet** (port 23) shows the Companion's log and debug output:
  ```
  telnet 192.168.0.33
  ```










