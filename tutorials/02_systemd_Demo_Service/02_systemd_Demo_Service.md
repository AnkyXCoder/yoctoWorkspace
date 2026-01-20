# Adding a **systemd** Service in Yocto

In this section, we will:

- Understand **systemd** in embedded Linux
- Create, package, and enable a **systemd** service using a BitBake recipe
- Enable and debug a service on target

## What is **systemd**?

**systemd** is the init system that:

- Starts services during boot
- Restarts crashed services
- Manages dependencies and logs

In Yocto, **systemd** services are packaged and enabled via recipes, not manually like desktop Linux.

## Step-by-Step Guide

### Step 1: Create Recipe Directory Structure

Create a new Recipe inside your custom layer:

```tree
meta-custom/
└── recipes-example/
    └── demo-service/
        ├── demo-service.bb
        └── files/
            ├── demo.sh
            └── demo.service
```

### Create a Simple Service Program

`demo.sh`

```sh
#!/bin/sh

echo "Demo systemd service started"
echo "PID is $$"

while true; do
    sleep 15
done
```

Make sure it is executable:

```bash
chmod +x demo.sh
```

This script:

- Prints a startup message
- Prints its PID
- Keeps running (required for long-running services)

### Step 3: Create the systemd Service File

`demo.service`

```ini
[Unit]
Description=Demo Yocto systemd Service
After=multi-user.target

[Service]
Type=simple
ExecStart=/usr/bin/demo-service
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
```

### Step 4: Create the BitBake Recipe

`demo-service.bb`

```bitbake
SUMMARY = "Demo systemd service example"
DESCRIPTION = "Simple systemd service for Yocto learning"
LICENSE = "MIT"

SRC_URI = " \
    file://demo.sh \
    file://demo.service \
"

S = "${WORKDIR}"

inherit systemd

SYSTEMD_SERVICE:${PN} = "demo.service"

do_install() {
    install -d ${D}${bindir}
    install -m 0755 demo.sh ${D}${bindir}/demo-service

    install -d ${D}${systemd_system_unitdir}
    install -m 0644 demo.service ${D}${systemd_system_unitdir}
}

FILES:${PN} += " \
    ${bindir}/demo-service \
    ${systemd_system_unitdir}/demo.service \
"
```

### Step 5: Enable systemd in Yocto Configuration

- Edit `local.conf`:

    ```bash
    vim build/conf/local.conf
    ```

- Ensure the following lines exist:

    ```conf
    DISTRO_FEATURES:append = " systemd"
    VIRTUAL-RUNTIME_init_manager = "systemd"
    ```

Note:
Without this, **systemd** services will not start.

### Step 6: Add the Service to the Image

Edit `recipes-core/core-image-base.bbappend` with following linesrecipes-core:

```conf
IMAGE_INSTALL:append = " demo-service"
```

This ensures the service is installed into the final root filesystem.

### Step 7: Rebuild the Image and Flash on SD Card

- Start the build for Raspberry Pi 4:

    ```bash
    bitbake core-image-base
    ```

After build completion, flash the image to SD card as described earlier.

### Step 8: Boot and Verify on Target

- Login via serial:

    ```bash
    root
    ```

- Check service status

    ```bash
    systemctl status demo.service
    ```

- Expected output:

    ```bash
    Active: active (running)
    ```

- View service logs

    ``` bash
    journalctl -u demo.service
    ```

- Expected output:

    ```bash
    Demo systemd service started
    PID is 123
    ```

- Verify binary location

    ```bash
    which demo-service
    ls -l /usr/bin/demo-service
    ```

### Step 9: Manual Testing

- Stop service:

    ```bash
    systemctl stop demo.service
    ```

- Run manually:

    ```bash
    systemctl start demo.service
    ```

- Restart service:

    ```bash
    systemctl restart demo.service
    ```


## ✅ What You Have Learned

✔ How **systemd** works in embedded Linux
✔ How Yocto installs and enables services
✔ How to debug services using `journalctl`
