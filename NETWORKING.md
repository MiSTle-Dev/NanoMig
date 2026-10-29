# Networking with NanoMig 1200

Please read [Networking](https://github.com/MiSTle-Dev/FPGA-Companion/tree/main/NETWORKING.md) first!  

To use the Internet with the NanoMig a **Pi-Pico W** or **Pi-Pico2 W** is mandatory.  
This file describes the installation and configuration of the network stack **Roadshow**. 

Make sure **PPP** is selected in the Settings menu under Serial:

<img width="600" height="459" alt="IMG_20261028_224427434_HDR" src="https://github.com/user-attachments/assets/300808a9-0d48-4f19-9910-21a3476032c1" />


Download and install **Roadshow**. Copy the **ppp-serial.device** from Storage to **Workbench:Devs/Networks/**

<img width="600" height="447" alt="IMG_20261028_222322933" src="https://github.com/user-attachments/assets/2e174276-568b-4afa-945d-76e532c7c2be" />

Copy the **PPP Netinterface** from Storage to **Workbench:Devs/Netinterfaces/**

<img width="600" height="462" alt="IMG_20261028_222343967" src="https://github.com/user-attachments/assets/25107f3e-9ef1-45eb-8d1c-9431d49c650c" />

Place a **PPP** configuration file anywhere you like. For example **S:** or **Preferences**

<img width="600" height="453" alt="IMG_20261028_222526108_HDR" src="https://github.com/user-attachments/assets/3b9504f6-7107-4003-af21-c4c4522ae266" />

Call the config file with ppp-dialer

<img width="600" height="447" alt="IMG_20261028_222608031_HDR" src="https://github.com/user-attachments/assets/f8d68899-137f-4e5c-a2a0-58b25120ac50" />
















