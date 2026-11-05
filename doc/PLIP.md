# PLIP (Amiga parallel port) networking on NanoMig

PLIP connects the Amiga to the network through the parallel port. The FPGA-Companion forwards the traffic to your WiFi/LAN, and the router does the NAT. The Amiga looks like a normal host of your network.

## Requirements
- NanoMig core built with `ENABLE_PLIP` (PLIP needs about 2 BSRAM and some hundred LUTs):
  - FX68K build (`src/tang/nano20k/top.sv`): PLIP is off by default. Uncomment `` `define ENABLE_PLIP ``. If the design no longer fits, disable `ENABLE_DRIVE_SOUNDS` and/or `ENABLE_AT_MODEM`.
  - TG68K/020 build (`src/tang/nano20k/top_020.sv`): `` `define ENABLE_PLIP `` and `` `define PLIP_LITE `` are enabled. `PLIP_LITE` drops the statistics and the loopback test to save logic, so the `[PLIP] LOOPBACK` option has no effect. This build is very tight on the GW2AR-18: `ENABLE_DRIVE_SOUNDS` and `ENABLE_AT_MODEM` are off, and if the design does not fit, enable `NO_WS2812` as well.
- FPGA-Companion firmware with PLIP support (branch `plip`), running on a Pico W or Pico 2 W that is connected to your WiFi.
- Roadshow on the Amiga, plus `plipbox.device`.

## 1. Companion (`config.ini`)
```ini
[PLIP]
ENABLE=1
PEER=192.168.1.66
```
- `PEER` is the Amiga's IP address. It must be an unused address in your LAN subnet. The Companion answers ARP requests for it (proxy ARP).
- Optional: `IP=` is the Companion's own address on the PLIP link (default `192.168.254.1`).
- Optional: `LOOPBACK=1` is a test mode for the core and is normally not needed.

## 2. Amiga (Roadshow)
Create `DEVS:NetInterfaces/plipbox`:
```
device=plipbox.device
address=192.168.1.66
netmask=255.255.255.0
downgoesoffline=yes
```
- `address` must equal `PEER` above.
- Remove `configure=dhcp`, otherwise Roadshow stays at 0.0.0.0.
- Set the default gateway (your router) in `DEVS:Internet/routes` and a DNS server in `DEVS:Internet/name_resolution` (see the Roadshow manual for the syntax).

Reboot the Amiga, or restart Roadshow, so the new settings are read.

## 3. Test
1. `ping` the Companion's LAN address (e.g. `192.168.1.33`).
2. `ping` your router.
3. `ping 1.1.1.1`.

If the first ping works and the others fail, check the gateway entry. If the Companion's log shows no `[PLIP]` lines, check that `ENABLE=1` is set and that WiFi is connected.

## Notes
- Measured throughput on a TG68K build: about 75 kB/s download and 92 kB/s upload. The FX68K build reached about 30 kB/s down and 25 kB/s up, measured against a different server.
- Using PLIP and serial PPP at the same time has not been tested.
