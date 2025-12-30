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
