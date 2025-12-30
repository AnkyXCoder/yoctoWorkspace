#!/usr/bin/env bash
set -euo pipefail

############################################
# Yocto Workspace Setup Script
# Ubuntu 22.04 / 24.04
############################################

WORKSPACE_DIR="$(pwd)/yoctoWorkspace"
VENV_DIR="${WORKSPACE_DIR}/.venv"

POKY_BRANCH="kirkstone"
META_RPI_BRANCH="kirkstone"
META_OE_BRANCH="kirkstone"

############################################
# Helper Functions
############################################
header() {
    echo
    echo "=================================================="
    echo "$1"
    echo "=================================================="
}

############################################
# OS Detection
############################################
header "Detecting Host OS"

source /etc/os-release

if [[ "$ID" != "ubuntu" ]]; then
    echo "ERROR: Unsupported OS: $ID"
    exit 1
fi

if [[ "$VERSION_ID" != "22.04" && "$VERSION_ID" != "24.04" ]]; then
    echo "ERROR: Unsupported Ubuntu version: $VERSION_ID"
    exit 1
fi

echo "Ubuntu ${VERSION_ID} detected ✔"

############################################
# Ubuntu Version-Based Package Mapping
############################################
header "Configuring Package List"

COMMON_PACKAGES=(
    gawk wget git diffstat unzip texinfo gcc build-essential
    chrpath socat cpio python3 python3-pexpect
    xz-utils debianutils iputils-ping
    file locales zstd lz4
    xterm
)

PYTHON_HOST_PACKAGES=(
    python3
    python3-pip
    python3-venv
)

GRAPHICS_PACKAGES=()

case "$VERSION_ID" in
    "22.04")
        GRAPHICS_PACKAGES+=(libegl1)
        ;;
    "24.04")
        GRAPHICS_PACKAGES+=(libegl1)
        ;;
esac

echo "Resolved packages for Ubuntu ${VERSION_ID}"

############################################
# Install Host Dependencies
############################################
header "Installing Host Dependencies"

sudo apt update
sudo apt install -y \
    "${COMMON_PACKAGES[@]}" \
    "${PYTHON_HOST_PACKAGES[@]}" \
    "${GRAPHICS_PACKAGES[@]}"

sudo locale-gen en_US.UTF-8
sudo update-locale LANG=en_US.UTF-8

echo "Host dependencies installed ✔"

############################################
# Create Workspace
############################################
header "Creating Yocto Workspace"

mkdir -p "${WORKSPACE_DIR}"
cd "${WORKSPACE_DIR}"

############################################
# Python Virtual Environment
############################################
header "Creating Python Virtual Environment"

python3 -m venv "${VENV_DIR}"

# Activate venv
source "${VENV_DIR}/bin/activate"

pip install --upgrade pip setuptools wheel

# Yocto-related Python tooling
pip install \
    jinja2 \
    GitPython \
    pylint \
    pyflakes \
    pytest

echo "Python virtual environment ready ✔"

############################################
# Clone Yocto Repositories
############################################
header "Cloning Yocto Repositories"

[[ -d poky ]] || git clone -b ${POKY_BRANCH} git://git.yoctoproject.org/poky
[[ -d meta-raspberrypi ]] || git clone -b ${META_RPI_BRANCH} https://github.com/agherzan/meta-raspberrypi.git
[[ -d meta-openembedded ]] || git clone -b ${META_OE_BRANCH} https://github.com/openembedded/meta-openembedded.git

echo "Yocto repositories cloned ✔"

############################################
# Environment Export Script
############################################
header "Creating Environment Export Script"

ENV_FILE="${WORKSPACE_DIR}/yocto-env.sh"

cat <<EOF > "${ENV_FILE}"

export YOCTO_WORKSPACE="${WORKSPACE_DIR}"
export POKY_DIR="\${YOCTO_WORKSPACE}/poky"
export META_RPI_DIR="\${POKY_DIR}/meta-raspberrypi"
export META_OE_DIR="\${POKY_DIR}/meta-openembedded"
export YOCTO_VENV="\${YOCTO_WORKSPACE}/.venv"

# Activate Python virtual environment
source "\${YOCTO_VENV}/bin/activate"
cd ${YOCTO_WORKSPACE}

# BitBake in PATH
export PATH="\${POKY_DIR}/bitbake/bin:\$PATH"

echo "Yocto environment loaded"
EOF

chmod +x "${ENV_FILE}"

############################################
# Workspace Layout
############################################
header "Yocto Workspace Layout"

tree -L 2 "${WORKSPACE_DIR}" || ls -R "${WORKSPACE_DIR}"

############################################
# Final Instructions
############################################
header "Setup Complete"

echo "Next steps:"
echo
echo "  source yoctoWorkspace/yocto-env.sh"
echo "  source poky/oe-init-build-env"
echo
echo "Yocto workspace ready ✔"
