# Yocto Build – Raspberry Pi 4 (Step-by-Step Guide)

This guide walks you through building your first Yocto image (core-image-base) for Raspberry Pi 4, flashing it to a microSD card, and connecting to the board via serial console for debugging.

## 📌 Prerequisites

### Host System

- Ubuntu 22.04 LTS (recommended)
- Minimum 50–70 GB free disk space
- Internet connection (downloads are large)

## Target Hardware

- Raspberry Pi 4 (4GB or 8GB recommended)
- microSD card (16GB or larger)
- USB-to-TTL serial cable (CP2102 / FTDI)
- HDMI + keyboard (optional)

## Step-by-Step Guide

### Step 1: Install Required Host Packages

Yocto requires specific development tools and libraries.

- Clone this repository.

    ```bash
    git clone git@github.com:AnkyXCoder/yoctoWorkspace.git
    ```

- Install dependencies using provided script.

  - This step
    - Clones poky
    - Clones meta-raspberrypi
    - Clones meta-openembedded

    ```bash
    chmod +x ./yoctoWorkspace/scripts/setup_yocto_workspace.sh
    ./yoctoWorkspace/scripts/setup_yocto_workspace.sh
    ```

✔ This installs all dependencies required by the Yocto Project.

- After successful setup, the directory structure should look like:

    ```tree
    yoctoWorkspace
    ├── layers
    │   ├── meta-openembedded
    │   └── meta-raspberrypi
    ├── poky
    ├── README.md
    ├── scripts
    │   └── setup_yocto_workspace.sh
    ├── tutorials
    ├── yocto-env.sh
    ```

### Step 2: Initialize the Yocto Build Environment

- Initialize Environment:

    ```bash
    source ./scripts/yocto-env.sh
    ```

- Initialize Build Environment:

    ```bash
    source poky/oe-init-build-env
    ```

### Step 3: Configure Build

- Add BSP layer `meta-raspberrypi` to `conf/bblayers.conf`:

    ```bash
    bitbake-layers add-layer ../layers/meta-raspberrypi
    ```

- Append the following lines to the end of `conf/local.conf`:

    ```conf
    MACHINE = "raspberrypi4"
    INIT_MANAGER = "systemd"
    LICENSE_FLAGS_ACCEPTED = "synaptics-killswitch"
    # Enable the UART
    ENABLE_UART = "1"
    ```

- For 64-bit Raspberry Pi 4 build, use:

    ```conf
    # For 64-bit Raspberry Pi 4 build
    MACHINE = "raspberrypi4-64"
    ```

### Step 4: Build the First Image (core-image-base)

- Start the build for Raspberry Pi 4:

    ```bash
    bitbake core-image-base
    ```

- Build time:

  - First build may take 1~3 hours depending on CPU & RAM
  - Subsequent builds are much faster

On success, images will be generated in:

```bash
build/tmp/deploy/images/raspberrypi4/
```

### Step 5: Identify the Image Files

Image files:

```bash
core-image-base-raspberrypi4.rootfs.wic.bz2
bcm2711-rpi-4-b.dtb
zImage
modules-raspberrypi4.tgz
```

The `.wic.bz2` file is the bootable SD card image.

### Step 6: Flash Image to microSD Card

1. Insert SD card and identify device

    ```bash
    lsblk
    ```

2. Unmount micro SD Card

    ```bash
    sudo umount /dev/sdX
    ```

    Replace `/dev/sdX` with your SD card device (e.g., `/dev/sda`).

3. Full Wipe (using dd)

   This overwrites everything, making data recovery very difficult (use with extreme caution!).

    ```bash
    sudo dd if=/dev/zero of=/dev/sdX bs=4M status=progress
    ```

    Replace `/dev/sdX` with your SD card device (e.g., `/dev/sda`).

    ⚠️ Be careful — wrong device will erase your system disk.

4. Decompress the image and Flash the image using `dd`

    ```bash
    bzcat build/tmp/deploy/images/raspberrypi4/core-image-base-raspberrypi4.rootfs.wic.bz2 | sudo dd of=/dev/sdX
    ```

    Replace `/dev/sdX` with your SD card device (e.g., `/dev/sda`).

    Example output:

    ```bash
    672562+0 records in
    672562+0 records out
    344351744 bytes (344 MB, 328 MiB) copied, 65.3482 s, 5.3 MB/s
    ```

### Step 7: Serial Console Connection (Debug)

- Raspberry Pi 4 UART Pins

| Signal | GPIO | Pin |
| ----- | ----- | ----- |
| TX | GPIO14 | Pin 8 |
| RX | GPIO15 | Pin 10 |
| GND | - | Pin 6 |

⚠️ Use 3.3V TTL only (NOT RS232)

- USB-to-TTL Connections

| USB-TTL | Raspberry Pi |
| ----- | ----- |
| RX | TX (GPIO14) |
| TX | RX (GPIO15) |
| GND | GND |

Refer to https://www.raspberrypi.com/documentation/computers/raspberry-pi.html#gpio

![alt text](raspberrypi-4b-gpio-expansion-header.png)

- Open Serial Terminal

    ```bash
    sudo minicom -D /dev/ttyUSB0 -b 115200
    ```

    or

    ```bash
    screen /dev/ttyUSB0 115200
    ```

### Step 8: Boot the Board

- Insert SD card into Raspberry Pi
- Connect serial cable
- Power ON the board
- You should see U-Boot → Kernel → Login prompt on serial console.

Example output:

```bash
Poky (Yocto Project Reference Distro) 5.0.14 raspberrypi4 tty0.163931] audit: type=1334 audit(1748544602.429:16): prog-id=19
raspberrypi4 login:
```

### Step 9: Login to the System

Default credentials:

```bash
username: root
password: (empty)
```

Verify OS:

```bash
root@raspberrypi4:~# uname -a
```

Example output:

```bash
Linux raspberrypi4 6.6.63-v7l
```

Verify OS details:

```bash
root@raspberrypi4:~# cat /etc/os-release
```

Example output:

```bash
ID=poky
NAME="Poky (Yocto Project Reference Distro)"
VERSION="5.0.14 (scarthgap)"
VERSION_ID=5.0.14
VERSION_CODENAME="scarthgap"
PRETTY_NAME="Poky (Yocto Project Reference Distro) 5.0.14 (scarthgap)"
CPE_NAME="cpe:/o:openembedded:poky:5.0.14"
```

## ✅ What You Have Achieved

✔ Built your first Yocto image
✔ Flashed Raspberry Pi 4 SD card
✔ Connected serial debug console
✔ Booted custom Embedded Linux
