# AutoRepack
This script is designed to make custom ROM flashings easier on the user. Note that this is **for Poco F3 device.**
Many recoveries still can't flash these ROMs and this tool allows you to convert them into TWRP friendly flashables.

It can also repack fastboot ROMS into recovery flashables so that user wouldn't need PC to handle these trivial stuff.

<img src="https://i.ibb.co/tH5VH1X/Screenshot-20220123-221636-Termux.png" width="200" height="400" />

As seen in the photo, there are certain options given to the user,
such as decryption patch, recovery and magisk (roots system) selections.
These are within users free will and are **not forced** upon unlike some other works out there.

<img src="https://i.ibb.co/zRHbNgG/Screenshot-20220123-221421-Termux.png" width="200" height="400" />

Custom recovery selection menu comes after TUI menu is okayed. In this menu, you can download, import
or remove recoveries and use them in your repack ROM.

<img src="https://i.ibb.co/k3KSZsk/Screenshot-20220123-221249-Termux.png" width="200" height="400" />

In case you quit the program in the middle of conversion and you want to continue where you left of,
Integrity Check is implemented to catch that situation and put you right back on track.

<img src="https://i.ibb.co/pLTHtkV/Screenshot-20220123-221311-Termux.png" width="200" height="400" />

Integrity Check also checks the workspace so that there's no residual files that might hinder the program.

<img src="https://i.ibb.co/Rpmq2Rd/Screenshot-20220123-221617-Termux.png" width="200" height="400" />

# Features:

- User Interface
- Fastboot-recovery conversion
- Compression to lessen repack size (auto detected if not given value)
- Flashable zip splitting to bypass 4G limit in recoveries.
- Granting partitions read-write access
- Can re-repack already repacked ROMs.
- Custom recovery options
- Custom magisk options
- Firmware selection
- Option to enable/disable encryption, magisk and recovery
- Remote updating, listing new and past updates, update reversing.

and many more..

This script is only usable in Android phones, our Telegram chat:

https://t.me/PocoF3DFE
