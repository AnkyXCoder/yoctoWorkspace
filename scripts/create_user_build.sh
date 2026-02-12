#!/usr/bin/env bash
set -euo pipefail

############################################
# Create a user-specific Yocto build directory
# - Reuses a shared downloads directory to save disk space
# - Copies existing build/conf as a template when available
############################################

usage() {
	cat <<EOF
Usage: $0 --name <build-name> [--downloads <path>] [--force]

Options:
	--name <build-name>    Name of the per-user build directory (required)
	--downloads <path>     Shared downloads directory to use (default: <workspace>/build/downloads)
	--force                Overwrite existing build directory
	--help                 Show this help

Examples:
	# Create a build using the workspace in YOCTO_WORKSPACE or ./yoctoWorkspace
	$0 --name alice-project

	# Create a build and point to a custom shared downloads directory
	$0 --name bob-project --downloads /srv/yocto/downloads

	# Overwrite an existing build directory
	$0 --name alice-project --force

Notes:
	The script reads the workspace from the environment variable YOCTO_WORKSPACE
	(fallback: ./yoctoWorkspace). The --workspace option was removed; set
	YOCTO_WORKSPACE instead when using a non-standard workspace path.
EOF
}

BUILD_NAME=""
DOWNLOADS_DIR=""
FORCE=0
WORKSPACE_DIR="${YOCTO_WORKSPACE:-}" || true

while [[ $# -gt 0 ]]; do
	case "$1" in
	--name)
		shift
		BUILD_NAME="${1:-}"
		shift
		;;
	--downloads)
		shift
		DOWNLOADS_DIR="${1:-}"
		shift
		;;
	--force)
		FORCE=1
		shift
		;;
	-h | --help)
		usage
		exit 0
		;;
	*)
		echo "Unknown option: $1"
		usage
		exit 1
		;;
	esac
done

if [[ -z "$BUILD_NAME" ]]; then
	echo "ERROR: --name is required"
	usage
	exit 1
fi

# Default workspace if not set in env or via option
if [[ -z "${WORKSPACE_DIR:-}" ]]; then
	WORKSPACE_DIR="$(pwd)/yoctoWorkspace"
fi

if [[ ! -d "${WORKSPACE_DIR}" ]]; then
	echo "ERROR: Workspace directory not found: ${WORKSPACE_DIR}"
	echo "Set YOCTO_WORKSPACE or pass --workspace"
	exit 1
fi

# Default shared downloads dir
if [[ -z "${DOWNLOADS_DIR}" ]]; then
	DOWNLOADS_DIR="${WORKSPACE_DIR}/build/downloads"
fi

DOWNLOADS_DIR="$(realpath -m "${DOWNLOADS_DIR}")"

if [[ ! -d "${DOWNLOADS_DIR}" ]]; then
	echo "Warning: downloads directory does not exist yet: ${DOWNLOADS_DIR}"
	echo "It will be created on first fetch by BitBake when building from this build dir."
fi

BASE_DIR="${WORKSPACE_DIR}/user-builds"
BUILD_DIR="${BASE_DIR}/${BUILD_NAME}"

if [[ -e "${BUILD_DIR}" && ${FORCE} -ne 1 ]]; then
	echo "ERROR: Build directory already exists: ${BUILD_DIR}"
	echo "Use --force to overwrite"
	exit 1
fi

rm -rf "${BUILD_DIR}"
mkdir -p "${BUILD_DIR}"

# If a template conf exists in workspace build/conf, copy it; otherwise create minimal conf
TEMPLATE_CONF_DIR="${WORKSPACE_DIR}/build/conf"
if [[ -d "${TEMPLATE_CONF_DIR}" ]]; then
	cp -a "${TEMPLATE_CONF_DIR}" "${BUILD_DIR}/conf"
else
	mkdir -p "${BUILD_DIR}/conf"
	cat >"${BUILD_DIR}/conf/local.conf" <<EOF
# Minimal local.conf created by create_user_build.sh
MACHINE ??= "raspberrypi4-64"
BB_NUMBER_THREADS ?= "$(nproc)"
PARALLEL_MAKE ?= "-j$(nproc)"
EOF
fi

LOCAL_CONF="${BUILD_DIR}/conf/local.conf"

if [[ ! -f "${LOCAL_CONF}" ]]; then
	touch "${LOCAL_CONF}"
fi

# Ensure DL_DIR is set to the shared downloads directory
if grep -Eq '^\s*DL_DIR\s*' "${LOCAL_CONF}" >/dev/null 2>&1; then
	sed -ri "s|^\s*DL_DIR.*|DL_DIR ?= \"${DOWNLOADS_DIR}\"|" "${LOCAL_CONF}"
else
	cat >>"${LOCAL_CONF}" <<EOF

# Use shared downloads directory to save disk across multiple builds
DL_DIR ?= "${DOWNLOADS_DIR}"
EOF
fi

echo "Created build directory: ${BUILD_DIR}"
echo
echo "Notes:"
echo "- This build uses shared downloads: ${DOWNLOADS_DIR}"
echo "- Template conf copied from: ${TEMPLATE_CONF_DIR}"
echo
echo "To start working in the new build directory run:"
echo
echo "  source ${WORKSPACE_DIR}/yocto-env.sh"
echo "  source \\${YOCTO_WORKSPACE}/sources/poky/oe-init-build-env ${BUILD_DIR}"
echo
echo "After sourcing the environment you can build as usual with bitbake."

exit 0
