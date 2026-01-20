# Creating Hello World Service

In this section, we will:

- Write a C++ application that prints **Hello World + current PID**
- Create a **Yocto recipe** for it
- Install it as a **systemd service**
- Verify it runs automatically on boot

## Step-by-Step Guide

### Step 1: Create and add a custom Layer

- Create a new custom layer

    ```bash
    bitbake-layers create-layer ../layers/meta-custom
    ```

    This command will create a new layer directory with necessary files:

    ```tree
    yoctoWorkspace/layers/meta-custom/
    ├── conf
    │   └── layer.conf
    ├── COPYING.MIT
    ├── README
    └── recipes-example
        └── example
            └── example_0.1.bb
    ```

- Add this custom layer

    ```bash
    bitbake-layers add-layer ../layers/meta-custom
    ```

- List added Layers

    ```bash
    bitbake-layers show-layers
    ```

    For example,

    ```bash
    layer                 path                                                                    priority
    ========================================================================================================
    core                  /home/einfochips/yoctoWorkspace/poky/meta                               5
    yocto                 /home/einfochips/yoctoWorkspace/poky/meta-poky                          5
    yoctobsp              /home/einfochips/yoctoWorkspace/poky/meta-yocto-bsp                     5
    raspberrypi           /home/einfochips/yoctoWorkspace/layers/meta-raspberrypi                 9
    meta-custom           /home/einfochips/yoctoWorkspace/layers/meta-custom                      6
    ```

### Step 2: Create the C++ Application

- Write a simple C/C++ application with infinite loop.
- Add a `CMakeLists.txt` to provide CMake build file.
- Why infinite loop?
  - Systemd services should stay alive unless explicitly designed as `oneshot`.

For example,

```tree
layers/meta-custom/
└── recipes-example/
    └── hello-service/
        └── files/
            ├── CMakeLists.txt
            └── hello.cpp
```

### Step 3: Create the **systemd** Service File

Create a `hello-service` file with following details:

```ini
[Unit]
Description=Hello World C++ Service
After=network.target

[Service]
Type=simple
ExecStart=/usr/bin/hello-service
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
```

Place this file in `hello-service` recipe directory:

```tree
layers/meta-custom/
└── recipes-example/
    └── hello-service/
        └── files/
            └── hello.service
```

### Step 4: Create the Yocto Recipe

Create the Yocto Recipe `hello-service.bb` file with following details:

```bitbake
SUMMARY = "Hello World C++ service using CMake"
DESCRIPTION = "C++ hello world service with PID printing"
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

SRC_URI = " \
    file://hello.cpp \
    file://CMakeLists.txt \
    file://hello.service \
"

S = "${WORKDIR}"

inherit cmake systemd

SYSTEMD_SERVICE:${PN} = "hello.service"

do_install:append() {
    install -d ${D}${systemd_system_unitdir}
    install -m 0644 ${S}/hello.service \
        ${D}${systemd_system_unitdir}
}

FILES:${PN} += " \
    ${bindir}/hello-service \
    ${systemd_system_unitdir}/hello.service \
"
```

Place `hello-service.bb` file in recipe directory:

```tree
layers/meta-custom/
└── recipes-example/
    └── hello-service/
        ├── hello-service.bb
```

Note:
You can find the list of pre-defined license files and their checksums in the `meta/files/common-licenses` directory of your Yocto/OpenEmbedded core layer.

### Step 5: Clean & Rebuild

Check if created Recipe compiles successfully.

```bash
bitbake hello-service -c cleansstate
bitbake hello-service
```

### Step 5: Enable **systemd** (If Not Enabled Already)

- Edit `local.conf`:

    ```bashe
    vim build/conf/local.conf
    ```

- Ensure the following lines exist::

    ```bash
    DISTRO_FEATURES:append = " systemd"
    VIRTUAL-RUNTIME_init_manager = "systemd"
    ```

### Step 6: Add Service to Image

Create `core-image-base.bbappend` with following lines and place it in `recipes-core` directory:

```conf
IMAGE_INSTALL:append = " hello-service"
```

```tree
layers/meta-custom/
└── recipes-core/
    └── images/
        ├── core-image-base.bbappend
```

### Step 7: Rebuild the Image

- Start the build for Raspberry Pi 4:

    ```bash
    bitbake core-image-base
    ```

This will:

- Compile the C++ app
- Install binary to /usr/bin
- Install service to /lib/systemd/system
- Enable service automatically

### Step 8: Flash Image to SD Card

(Use the same flashing steps from [How to Build Yocto](tutorials/00_Build_Yocto/00_Build_Yocto.md))

```bash
bzcat build/tmp/deploy/images/raspberrypi4/core-image-base-raspberrypi4.rootfs.wic.bz2 | sudo dd of=/dev/sdX status=progress conv=fsync
```

Replace `/dev/sdX` with your SD card device (e.g., `/dev/sda`).

### Step 9: Boot and Connect via Serial

- Open Serial Terminal

    ```bash
    sudo minicom -D /dev/ttyUSB0 -b 115200
    ```

### Step 10: Verify the Service

- Check service status

    ```bash
    systemctl status hello.service
    ```

    Expected:

    Active: active (running)

- View logs

    ```bash
    journalctl -u hello.service
    ```

    Output:

    ```bash
    Hello World from Yocto! Current PID: 123
    ```

- Verify binary

    ```bash
    which hello-service
    ls -l /usr/bin/hello-service
    ```

### Step 10: Manual Testing

- Stop service:

    ```bash
    systemctl stop hello.service
    ```

- Run manually:

    ```bash
    /usr/bin/hello-service
    ```

## ✅ What You Learned

✔ C++ application with CMake and signal handling (SIGTERM)
✔ C++ application cross-compiled by Yocto
✔ Writing a custom BitBake recipe
✔ Installing and enabling `systemd` services
✔ Debugging using `journalctl`
