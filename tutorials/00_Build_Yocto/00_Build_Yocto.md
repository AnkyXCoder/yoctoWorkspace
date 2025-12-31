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

    ```shell
    git clone git@github.com:AnkyXCoder/yoctoWorkspace.git
    ```

- Install dependencies using provided script.

  - This step
    - Clones poky
    - Clones meta-raspberrypi
    - Clones meta-openembedded

    ```shell
    chmod +x ./yoctoWorkspace/scripts/setup_yocto_workspace.sh
    ./yoctoWorkspace/scripts/setup_yocto_workspace.sh
    ```

✔ This installs all dependencies required by the Yocto Project.

### Step 2: Initialize the Yocto Build Environment

- Initialize Environment:

    ```shell
    source ./scripts/yocto-env.sh
    ```

- Initialize Build Environment:

    ```shell
    source poky/oe-init-build-env
    ```

### Step 3: Configure Build

- Add BSP layer meta-raspberrypi to `conf/bblayers.conf`:

    ```shell
    bitbake-layers add-layer ../meta-raspberrypi
    ```

- Append the following 3 lines to the end of `conf/local.conf`:

    ```conf
    MACHINE = "raspberrypi5"
    INIT_MANAGER = "systemd"
    LICENSE_FLAGS_ACCEPTED = "synaptics-killswitch"
    ```

### Step 4: Build the First Image (core-image-base)

- Start the build for Raspberry Pi 4:

    ```shell
    bitbake core-image-base
    ```

- Build time:

  - First build may take 1~3 hours depending on CPU & RAM
  - Subsequent builds are much faster

On success, images will be generated in:

```shell
build/tmp/deploy/images/raspberrypi4/
```

### Step 5: Identify the Image Files

Image files:

```shell
core-image-base-raspberrypi4.wic.bz2
bcm2711-rpi-4-b.dtb
Image
modules-*.tgz
```

The `.wic.bz2` file is the bootable SD card image.

### Step 6: Flash Image to microSD Card

1. Insert SD card and identify device

```shell
lsblk
```

Example device: `/dev/sdb`

⚠️ Be careful — wrong device will erase your system disk

2️. Decompress the image

```shell
bunzip2 core-image-base-raspberrypi4-64.wic.bz2
```

3️. Flash using `dd`

```shell
sudo dd if=core-image-base-raspberrypi4-64.wic \
        of=/dev/sdX bs=4M status=progress conv=fsync
```

Replace `/dev/sdX` with your SD card device (e.g., `/dev/sdb`).

### Step 7: Serial Console Connection (Debug)

- Raspberry Pi 4 UART Pins

| Signal | GPIO | Pin |
| TX | GPIO14 | Pin 8 |
| RX | GPIO15 | Pin 10 |
| GND | - | Pin 6 |

⚠️ Use 3.3V TTL only (NOT RS232)

- USB-to-TTL Connections

| USB-TTL | Raspberry Pi |
| RX | TX (GPIO14) |
| TX | RX (GPIO15) |
| GND | GND |

- Open Serial Terminal

    ```shell
    sudo minicom -D /dev/ttyUSB0 -b 115200
    ```

    or

    ```shell
    screen /dev/ttyUSB0 115200
    ```

### Step 8: Boot the Board

- Insert SD card into Raspberry Pi
- Connect serial cable
- Power ON the board
- You should see U-Boot → Kernel → Login prompt on serial console.

### Step 9: Login to the System

Default credentials:

```shell
username: root
password: (empty)
```

Verify system:

```shell
uname -a
cat /etc/os-release
```
