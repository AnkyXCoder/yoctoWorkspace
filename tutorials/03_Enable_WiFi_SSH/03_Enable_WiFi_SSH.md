# Enable Wi-Fi and SSH

In this section, we will:

- Enable onboard Raspberry Pi Wi-Fi
- Connect to a Wi-Fi network automatically at boot
- Enable SSH server in Yocto
- Access the device remotely over SSH

Yocto uses the following components for Wi-Fi + SSH:

- `wpa_supplicant` – Wi-Fi authentication
- `systemd` – service management
- `OpenSSH` – SSH server
- Linux kernel drivers for Broadcom Wi-Fi (Raspberry Pi 4)

## Step-by-Step Guide

### Step 1: Enable Wi-Fi and SSH Packages in Yocto

- Edit Yocto Build configuration:

    ```bash
    vim conf/local.conf
    ```

- Add or ensure the following lines exist:

    ```bash
    # Enable systemd
    DISTRO_FEATURES:append = " systemd wifi"
    VIRTUAL-RUNTIME_init_manager = "systemd"

    # Install Wi-Fi + SSH packages
    IMAGE_INSTALL:append = " \
        wpa-supplicant \
        iw \
        linux-firmware-bcm43430 \
        linux-firmware-bcm43455 \
        openssh \
    "
    ```

📌 Notes:

- `linux-firmware-bcm43455` is required for Raspberry Pi 4
- `iw` is a Wi-Fi debug utility
- `openssh` provides `sshd`

### Step 2: Add text editor

You can use different text editors. For simplicity, use `vim`.

- Add to `local.conf`:

    ```conf
    # Add text editors on Boot-up
    IMAGE_INSTALL:append = " vim"
    ```

`systemd-networkd` is enabled automatically when systemd is used.

### Step 3: Rebuild the Image and Flash on SD Card

- Start the build for Raspberry Pi 4:

    ```bash
    bitbake core-image-base -c cleansstate
    bitbake core-image-base
    ```

After build completion, flash the image to SD card as described earlier.

### PART A: Add Wi-Fi configurations at Runtime

#### Step 4: Create Wi-Fi Configuration (wpa_supplicant)

On the target device, create the Wi-Fi configuration file.

- Login via serial console:

    ```bash
    root
    ```

- Create directory:

    ```bash
    mkdir -p /etc/wpa_supplicant
    ```

- Create config file:

    ```bash
    nano /etc/wpa_supplicant/wpa_supplicant.conf
    ```

- Add:

    ```conf
    ctrl_interface=/run/wpa_supplicant
    update_config=1
    country=IN

    network={
        ssid="YOUR_WIFI_SSID"
        psk="YOUR_WIFI_PASSWORD"
    }
    ```

📌 Replace SSID and password accordingly.
📌 Set correct country code for regulatory compliance.

#### Step 5: Start Wi-Fi Manually (First Test)

- Bring up the Wi-Fi interface:

    ```bash
    ip link set wlan0 up
    ```

- Start `wpa_supplicant`:

    ```bash
    wpa_supplicant -B -i wlan0 -c /etc/wpa_supplicant/wpa_supplicant.conf
    ```

- Request IP address:

    ```bash
    udhcpc -i wlan0
    ```

- Verify connection:

    ```bash
    ip addr show wlan0
    ping -c 3 google.com
    ```

✔ If ping works, Wi-Fi is functional.

#### Step 6: Enable Wi-Fi at Boot (systemd)

- Enable `wpa_supplicant` service:

    ```bash
    systemctl enable wpa_supplicant@wlan0.service
    systemctl start wpa_supplicant@wlan0.service
    ```

- Check status:

    ```bash
    systemctl status wpa_supplicant@wlan0.service
    ```

#### Step 7: Enable SSH Service

- Start SSH daemon:

    ```bash
    systemctl start sshd
    systemctl enable sshd
    ```

- Check status:

    ```bash
    systemctl status sshd
    ```

#### Step 8: Find Device IP Address

- Fetch Device IP Address

    ```bash
    ip addr show wlan0
    ```

Example output:

```bash
inet 192.168.1.45/24
```

#### Step 9: SSH from Host Machine

- From your development PC:

```bash
ssh root@<raspberry_pi4_ip_address>
```

(Default password is empty.)

✔ You are now connected via SSH.

#### Step 10: Debugging Wi-Fi Issues

- Check kernel driver

    ```bash
    dmesg | grep wlan
    ```

- Check firmware loading

    ```bash
    dmesg | grep firmware
    ```

- Check service logs

    ```bash
    journalctl -u wpa_supplicant@wlan0
    ```

- Scan for networks

    ```bash
    iw dev wlan0 scan | less
    ```

### PART B: Add Wi-Fi configurations and Ethernet Fallback at Build Time

#### Step 4: Create a Custom Wi-Fi Config Recipe

```tree
meta-custom/
└── recipes-connectivity/
    └── wifi-config/
        ├── wifi-config.bb
        └── files/
            └── wpa_supplicant.conf
```

#### Step 5: Create wpa_supplicant.conf

files/wpa_supplicant.conf

```conf
ctrl_interface=/run/wpa_supplicant
update_config=1
country=IN

network={
    ssid="MY_WIFI_SSID"
    psk="MY_WIFI_PASSWORD"
    key_mgmt=WPA-PSK
}
```

📌 For production: generate this file dynamically or encrypt credentials.

#### Step 6: Create the BitBake Recipe

wifi-config.bb

```bitbake
SUMMARY = "Preconfigured Wi-Fi setup"
LICENSE = "MIT"

SRC_URI = "file://wpa_supplicant.conf"

do_install() {
    install -d ${D}/etc/wpa_supplicant
    install -m 0600 wpa_supplicant.conf \
        ${D}/etc/wpa_supplicant/wpa_supplicant.conf
}

FILES:${PN} += "/etc/wpa_supplicant/wpa_supplicant.conf"
```

#### Step 7: Add to Image

In build/conf/local.conf:

```conf
IMAGE_INSTALL:append = " wifi-config wpa-supplicant iw"
```

#### Step 8: Create Network Configuration

```tree
meta-custom/
└── recipes-connectivity/
    └── network-config/
        ├── network-config.bb
        └── files/
            ├── eth0.network
            └── wlan0.network
```

`eth0.network`

```ini
[Match]
Name=eth0

[Network]
DHCP=yes
```

`wlan0.network`
```ini
[Match]
Name=wlan0

[Network]
DHCP=yes
```

`network-config.bb`

```bitbake
SUMMARY = "Network configuration for Ethernet and Wi-Fi"
LICENSE = "MIT"

SRC_URI = " \
    file://eth0.network \
    file://wlan0.network \
"

do_install() {
    install -d ${D}${sysconfdir}/systemd/network

    install -m 0644 eth0.network \
        ${D}${sysconfdir}/systemd/network/

    install -m 0644 wlan0.network \
        ${D}${sysconfdir}/systemd/network/
}

FILES:${PN} += "${sysconfdir}/systemd/network"
```

- Enable systemd-networkd

In local.conf:

```conf
IMAGE_INSTALL:append = " systemd-networkd"
```


✅ What You Have Learned

✔ Enable Wi-Fi in Yocto
✔ Configure wpa_supplicant
✔ Use systemd services
✔ Enable and access SSH
✔ Debug network issues on embedded Linux
