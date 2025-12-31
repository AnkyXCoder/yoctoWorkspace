#!/usr/bin/env bash
set -euo pipefail

############################################
# Yocto Workspace Setup Script
# Ubuntu 22.04 / 24.04
############################################

WORKSPACE_DIR="$(pwd)/yoctoWorkspace"
VENV_DIR="${WORKSPACE_DIR}/.venv"

# Defaults
YOCTO_RELEASE_DEFAULT="scarthgap"
POKY_BRANCH="${YOCTO_RELEASE_DEFAULT}"
META_RPI_BRANCH="${YOCTO_RELEASE_DEFAULT}"
META_OE_BRANCH="${YOCTO_RELEASE_DEFAULT}"
META_RUST_BRANCH="${YOCTO_RELEASE_DEFAULT}"
META_BBB_BRANCH="${YOCTO_RELEASE_DEFAULT}"

# Defaults for machine
MACHINE_DEFAULT="raspberrypi"
MACHINE="${MACHINE_DEFAULT}"

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
# CLI Options
############################################
show_help() {
    cat <<EOF
Usage: $0 [--release <release>] [--machine <machine>] [--help]
  --release <release>   Yocto release to use (default: ${YOCTO_RELEASE_DEFAULT})
  --machine <machine>   Target machine (default: ${MACHINE_DEFAULT})
  --help                Show this help
EOF
}

# Parse CLI options
while [[ $# -gt 0 ]]; do
    case "$1" in
        --release)
            shift
            if [[ -z "${1:-}" ]]; then echo "ERROR: --release requires an argument"; exit 1; fi
            YOCTO_RELEASE="$1"
            shift
            ;;
        --machine)
            shift
            if [[ -z "${1:-}" ]]; then echo "ERROR: --machine requires an argument"; exit 1; fi
            MACHINE="$1"
            shift
            ;;
        -h|--help)
            show_help
            exit 0
            ;;
        *)
            echo "ERROR: Unknown option: $1"
            show_help
            exit 1
            ;;
    esac
done

# Apply release defaults
POKY_BRANCH="${YOCTO_RELEASE:-${YOCTO_RELEASE_DEFAULT}}"
META_OE_BRANCH="${YOCTO_RELEASE:-${YOCTO_RELEASE_DEFAULT}}"
META_RUST_BRANCH="${YOCTO_RELEASE:-${YOCTO_RELEASE_DEFAULT}}"
META_RPI_BRANCH="${YOCTO_RELEASE:-${YOCTO_RELEASE_DEFAULT}}"
META_BBB_BRANCH="${YOCTO_RELEASE:-${YOCTO_RELEASE_DEFAULT}}"

# Apply machine default
MACHINE="${MACHINE:-${MACHINE_DEFAULT}}"

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
    file locales zstd lz4 gparted minicom
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

POKY_REPO="git://git.yoctoproject.org/poky"
META_RPI_REPO="https://github.com/agherzan/meta-raspberrypi.git"
META_OE_REPO="https://github.com/openembedded/meta-openembedded.git"
META_RUST_REPO="https://github.com/meta-rust/meta-rust.git"
META_BBB_REPO="https://github.com/jumpnow/meta-bbb.git"

# Create layers directory
mkdir -p layers

clone_with_branch() {
    local dir="$1"; shift
    local branch="$1"; shift
    local repo="$1"; shift

    if [[ -d "${dir}" ]]; then
        echo "Directory ${dir} already exists."
        if [[ -d "${dir}/.git" ]]; then
            echo "Updating existing git repo in ${dir} and checking out branch ${branch} (if available)..."
            # fetch latest refs
            git -C "${dir}" fetch --all --prune || true

            # Prefer remote branch if available
            if git -C "${dir}" ls-remote --exit-code --heads origin "${branch}" >/dev/null 2>&1; then
                # Try to checkout the branch (create local tracking branch if needed)
                if git -C "${dir}" rev-parse --verify "${branch}" >/dev/null 2>&1; then
                    git -C "${dir}" checkout "${branch}" || true
                else
                    git -C "${dir}" checkout -b "${branch}" "origin/${branch}" || true
                fi

                # Attempt to fast-forward/pull
                git -C "${dir}" pull --ff-only origin "${branch}" || true
            else
                echo "Warning: branch ${branch} not found in remote for ${repo}; leaving current branch as-is."
            fi
        else
            echo "Warning: ${dir} exists but is not a git repository; skipping branch checkout."
        fi
        return
    fi

    echo "Cloning ${repo} (branch: ${branch}) into ${dir}..."
    if ! git clone -b "${branch}" "${repo}" "${dir}" 2>/dev/null; then
        echo "Warning: branch ${branch} not found for ${repo}, cloning default branch..."
        git clone "${repo}" "${dir}"
    fi
}

clone_with_branch "poky" "${POKY_BRANCH}" "${POKY_REPO}"

# Common layers
clone_with_branch "layers/meta-openembedded" "${META_OE_BRANCH}" "${META_OE_REPO}"
clone_with_branch "layers/meta-rust" "${META_RUST_BRANCH}" "${META_RUST_REPO}"

# Machine-specific BSP layers
case "${MACHINE,,}" in
    raspberry*|rpi*|raspberrypi)
        clone_with_branch "layers/meta-raspberrypi" "${META_RPI_BRANCH}" "${META_RPI_REPO}"
        ;;
    beaglebone*|bbb|beaglebone-black|beaglebone-yocto)
        clone_with_branch "layers/meta-bbb" "${META_BBB_BRANCH}" "${META_BBB_REPO}"
        ;;
    *)
        echo "Note: No BSP-specific layers is configured for machine '${MACHINE}'."
        echo "You may need to add a BSP layers manually after setup."
        ;;
esac

echo "Yocto repositories cloned ✔"

############################################
# Environment Export Script
############################################
header "Creating Environment Export Script"

ENV_FILE="${WORKSPACE_DIR}/yocto-env.sh"

cat <<EOF > "${ENV_FILE}"

export YOCTO_WORKSPACE="${WORKSPACE_DIR}"
export YOCTO_RELEASE="${POKY_BRANCH}"
export YOCTO_MACHINE="${MACHINE}"
export POKY_DIR="\${YOCTO_WORKSPACE}/poky"
export META_RPI_DIR="\${YOCTO_WORKSPACE}/layers/meta-raspberrypi"
export META_OE_DIR="\${YOCTO_WORKSPACE}/layers/meta-openembedded"
export META_RUST_DIR="\${YOCTO_WORKSPACE}/layers/meta-rust"
export META_BBB_DIR="\${YOCTO_WORKSPACE}/layers/meta-bbb"
export YOCTO_VENV="\${YOCTO_WORKSPACE}/.venv"

# Activate Python virtual environment
source "\${YOCTO_VENV}/bin/activate"
cd \${YOCTO_WORKSPACE}

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
