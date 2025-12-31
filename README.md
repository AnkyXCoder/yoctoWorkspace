# Yocto Project Learning

A structured, beginner-to-advanced learning repository for Yocto Project.

## Supported Boards

- [x] Raspberry Pi 4B Board

## Quick Start

### What is Yocto?

THE YOCTO PROJECT. IT'S NOT AN EMBEDDED LINUX DISTRIBUTION, IT CREATES A CUSTOM ONE FOR YOU.

https://www.yoctoproject.org/

### Why to use Yocto?

- To configure the Linux according to our specs.
- The Image contains what we need.
- No extra packages.
- Small Image Size.

## Setup Host PC

### OS

- Ubuntu 24.04 (LTS)

### Editor

- Install Vim

    ```bash
    sudo apt update
    sudo apt-get install vim
    ```

### Yocto Workspace Setup

This repository includes a script to install dependencies, packages and clone necessary repositories.

- Clone this repository.
- Install and setup Yocto Workspace for Raspberry Pi.

    ```bash
    ./yoctoWorkspace/scripts/setup_yocto_workspace.sh
    ```

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

## Setup script

The repository provides `scripts/setup_yocto_workspace.sh` to create a workspace and clone required layers.

Usage:

```bash
./scripts/setup_yocto_workspace.sh [--release <release>] [--machine <machine>]
```

- **--release**: Yocto release to use (default: **scarthgap**)
- **--machine**: Target machine (default: **raspberrypi**)

Examples:

- Default (Scarthgap, Raspberry Pi):

    ```bash
    ./scripts/setup_yocto_workspace.sh
    ```

- BeagleBone (will clone `meta-bbb` from https://github.com/jumpnow/meta-bbb):

    ```bash
    ./scripts/setup_yocto_workspace.sh --machine beaglebone
    ```

The script clones only the layers relevant to the selected `--machine` (plus common layers) and will use the branch matching `--release` when possible. If your machine isn't covered by a built-in BSP, add the BSP layer manually after setup.

## Tutorials

- [How to Build Yocto](tutorials/00_Build_Yocto/00_Build_Yocto.md)
  - Step-by-step guide to build a Yocto image for Raspberry Pi.

