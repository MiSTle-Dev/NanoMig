# Networking with NanoMig 1200

Please read [Networking](https://github.com/MiSTle-Dev/FPGA-Companion/tree/main/NETWORKING.md) first!  

To use the Internet with the NanoMig a **Pi-Pico W** or **Pi-Pico2 W** is mandatory.  
This file describes the installation and configuration of the network stack **Roadshow**. 

Make sure **PPP** is selected in the Settings menu under Serial:

<img width="600" height="450" alt="IMG_20261028_224427434_HDR" src="https://github.com/user-attachments/assets/de1d7bd7-f0d1-4958-a79e-2c5bab96ed25" />

Download and install Roadshow. Copy the ppp-serial.device to **Workbench:Devs/Networks/**

<img width="2048" height="1536" alt="IMG_20261028_222322933" src="https://github.com/user-attachments/assets/36a4d894-88ed-47a6-8cf1-dc50b279513d" />

Copy PPP to **Workbench:Devs/Netinterfaces/**

<img width="2048" height="1536" alt="IMG_20261028_222343967" src="https://github.com/user-attachments/assets/f4fc297f-1938-4ff4-9aa3-7378c4a16f2d" />

<img width="2048" height="1536" alt="IMG_20261028_222414271" src="https://github.com/user-attachments/assets/282a2915-b0bc-4218-8349-2b7ffe7e339d" />

Place a **PPP** configuration file anywhere you like. E.g. S: or Preferences

<img width="1865" height="1428" alt="IMG_20261028_222526108_HDR" src="https://github.com/user-attachments/assets/fb43cf3c-2617-4e87-a862-e08d301be561" />

Call the config file with ppp-dialer

<img width="4096" height="3072" alt="IMG_20261028_222608031_HDR" src="https://github.com/user-attachments/assets/8f535ae1-5841-479e-8052-103145bd7981" />















