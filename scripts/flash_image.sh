#!/usr/bin/env bash
set -euo pipefail

REMOTE=""
REMOTE_HOST=""
REMOTE_REL=""
DEVICE=""
LOCAL_DIR=""
ASSUME_YES=0
FORCE_LOCAL_FILE=""

# directories and timestamps
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
WORKSPACE_DIR=$(cd "$SCRIPT_DIR/.." && pwd)
IMAGES_DIR="$WORKSPACE_DIR/images"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
TARGET_DIR=""

# locate script directory and config
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
YOCTO_ENV_LOCAL="$SCRIPT_DIR/../yocto-env.sh"

# determine MACHINE from local yocto-env.sh without sourcing (avoid activating venv)
MACHINE=""
if [[ -f "$YOCTO_ENV_LOCAL" ]]; then
	MACHINE=$(awk -F= '/^export[[:space:]]+YOCTO_MACHINE=/{gsub(/"/,"",$2); gsub(/^[ \t]+|[ \t]+$/,"",$2); print $2}' "$YOCTO_ENV_LOCAL" | tr -d '\r') || true
fi
if [[ -z "$MACHINE" ]]; then
	MACHINE="raspberrypi4-64"
fi

print_help() {
	cat <<EOF
Usage: $(basename "$0") [options]

Common usages:
	1) Provide a full remote file:
		 $(basename "$0") -r user@host:/path/to/core-image-base-<MACHINE>.rootfs.wic.bz2 -d /dev/sdX

	2) Construct the remote path from host + remote workspace path:
		 $(basename "$0") -H user@host -p remote/yoctoWorkspace -d /dev/sdX

	3) Flash a pre-downloaded local file (copied into images/<timestamp>/):
		 $(basename "$0") -F /path/to/core-image-base-<MACHINE>.rootfs.wic.bz2 -d /dev/sdX

Options:
	-r <remote>    Full remote source (scp/rsync style), e.g. user@host:/home/user/yoctoWorkspace/build/tmp/.../file.bz2
	-H <host>      Remote host (user@host) used with -p to auto-build the image path
	-p <build_dir> Remote path to the Yocto build directory on the remote host
				 (e.g. /home/user/yoctoWorkspace/build or simply build).
	-F <file>      Use a local, pre-downloaded image file (will be copied into images/<timestamp>/)
	-d <device>    Target block device to flash (e.g. /dev/sdb). If omitted, the script will prompt for it
	-l <local_dir> Local directory root to store images (default: <workspace>/images)
	-y             Skip interactive confirmation prompts (use with caution)
	-h             Show this help

Behavior notes:
	- Downloaded or copied images are placed in: <workspace>/images/<timestamp>/
	- The script will attempt to detect YOCTO_MACHINE from $(yocto-env.sh) and build
		the standard path from the remote build dir: <build>/tmp/deploy/images/<MACHINE>/core-image-base-<MACHINE>.rootfs.wic.bz2
	- If you provide -H and -p, the remote path is constructed from the supplied
		build directory.

Examples:
	# construct path from remote build directory and flash (interactive device prompt allowed)
	./scripts/$(basename "$0") -H user@host -p /home/user/yoctoWorkspace/build

	# use a pre-downloaded file and prompt for device
	./scripts/$(basename "$0") -F /tmp/core-image-base-raspberrypi4.rootfs.wic.bz2

	# non-interactive: download from remote and write to /dev/sdb (DANGEROUS)
	sudo ./scripts/$(basename "$0") -r user@host:/home/user/yoctoWorkspace/build/tmp/deploy/images/raspberrypi4/core-image-base-raspberrypi4.rootfs.wic.bz2 -d /dev/sdb -y

	# download and keep images in custom storage dir (remote build dir provided)
	./scripts/$(basename "$0") -H user@host -p /home/user/yoctoWorkspace/build -l /tmp/my_images

EOF
}

while getopts ":r:H:p:d:l:F:yh" opt; do
	case ${opt} in
	r) REMOTE="$OPTARG" ;;
	H) REMOTE_HOST="$OPTARG" ;;
	p) REMOTE_REL="$OPTARG" ;;
	d) DEVICE="$OPTARG" ;;
	l) LOCAL_DIR="$OPTARG" ;;
	F) FORCE_LOCAL_FILE="$OPTARG" ;;
	y) ASSUME_YES=1 ;;
	h)
		print_help
		exit 0
		;;
	:)
		echo "Missing arg for -$OPTARG"
		print_help
		exit 2
		;;
	*)
		print_help
		exit 2
		;;
	esac
done

# prepare target images directory (timestamped)
TARGET_DIR="$IMAGES_DIR/$TIMESTAMP"
if [[ -n "$LOCAL_DIR" ]]; then
	TARGET_DIR="$LOCAL_DIR/$TIMESTAMP"
fi
mkdir -p "$TARGET_DIR"

# If a local force file provided, copy it into the timestamped dir
if [[ -n "$FORCE_LOCAL_FILE" ]]; then
	if [[ ! -f "$FORCE_LOCAL_FILE" ]]; then
		echo "Error: provided local file $FORCE_LOCAL_FILE not found." >&2
		exit 4
	fi
	FNAME=$(basename -- "$FORCE_LOCAL_FILE")
	cp -a "$FORCE_LOCAL_FILE" "$TARGET_DIR/"
	LOCAL_PATH="$TARGET_DIR/$FNAME"
	echo "Copied local file to $LOCAL_PATH"
else
	# If REMOTE not provided, build from REMOTE_HOST + REMOTE_REL + MACHINE
	if [[ -z "$REMOTE" ]]; then
		# If a build dir was provided via -p, construct the remote path from it
		if [[ -n "$REMOTE_REL" && -n "$REMOTE_HOST" ]]; then
			REMOTE="${REMOTE_HOST}:${REMOTE_REL%/}/tmp/deploy/images/${MACHINE}/core-image-base-${MACHINE}.rootfs.wic.bz2"
			echo "Using constructed remote path: $REMOTE"
		else
			echo "Error: either provide -r (full remote path), -F (local file), or both -H and -p to construct the path." >&2
			print_help
			exit 2
		fi
	fi

	FNAME=$(basename -- "$REMOTE")
	LOCAL_PATH="$TARGET_DIR/$FNAME"
	echo "Downloading $REMOTE -> $TARGET_DIR/"

	# Resolve remote symlink (if any) so we fetch the actual file target.
	RESOLVED_REMOTE="$REMOTE"
	if [[ "$REMOTE" == *:* ]]; then
		REMOTE_USER_HOST="${REMOTE%%:*}"
		REMOTE_PATH="${REMOTE#*:}"
		# Attempt to resolve the remote path to the real file via ssh. If this fails, fall back to the original path.
		RESOLVED_PATH=$(ssh -o BatchMode=yes -o ConnectTimeout=10 "$REMOTE_USER_HOST" "readlink -f -- '$REMOTE_PATH' 2>/dev/null || echo '$REMOTE_PATH'" 2>/dev/null || true)
		if [[ -n "$RESOLVED_PATH" ]]; then
			RESOLVED_REMOTE="${REMOTE_USER_HOST}:${RESOLVED_PATH}"
			echo "Resolved remote path: $RESOLVED_REMOTE"
		fi
	fi

	# Try rsync first (copy symlink target with -L), fall back to scp on failure.
	DOWNLOAD_OK=0
	if command -v rsync >/dev/null 2>&1; then
		echo "Attempting rsync (copying symlink target)..."
		RSYNC_CMD=(rsync -avPL --partial "$RESOLVED_REMOTE" "$TARGET_DIR/")
		echo "Running: ${RSYNC_CMD[*]}"
		if "${RSYNC_CMD[@]}"; then
			DOWNLOAD_OK=1
		else
			echo "rsync failed, will try scp fallback" >&2
		fi
	fi
	if [[ $DOWNLOAD_OK -eq 0 ]]; then
		echo "Attempting scp..."
		SCP_CMD=(scp "$RESOLVED_REMOTE" "$TARGET_DIR/")
		echo "Running: ${SCP_CMD[*]}"
		if "${SCP_CMD[@]}"; then
			DOWNLOAD_OK=1
		else
			echo "scp failed to download $RESOLVED_REMOTE" >&2
		fi
	fi

	# If no download method succeeded, fail early and do not proceed to flashing.
	if [[ $DOWNLOAD_OK -eq 0 ]]; then
		echo "Error: all download methods failed for $RESOLVED_REMOTE" >&2
		exit 4
	fi

	# Determine the actual downloaded file. Prefer the expected basename, otherwise pick the newest file in the target dir.
	if [[ ! -f "$LOCAL_PATH" ]]; then
		# pick newest regular file in TARGET_DIR
		NEWEST=$(ls -t "$TARGET_DIR"/* 2>/dev/null | head -n1 || true)
		if [[ -n "$NEWEST" && -f "$NEWEST" ]]; then
			LOCAL_PATH="$NEWEST"
			echo "Warning: expected filename not found; using $LOCAL_PATH"
		else
			echo "Error: download failed, no files found in $TARGET_DIR" >&2
			exit 4
		fi
	fi

	if [[ -f "$LOCAL_PATH" && -L "$LOCAL_PATH" ]]; then
		# If rsync created a symlink, resolve it locally
		REAL_LOCAL=$(readlink -f "$LOCAL_PATH" || true)
		if [[ -n "$REAL_LOCAL" && -f "$REAL_LOCAL" ]]; then
			LOCAL_PATH="$REAL_LOCAL"
			echo "Resolved local symlink to $LOCAL_PATH"
		fi
	fi
	echo "Downloaded: $LOCAL_PATH (size: $(stat -c%s "$LOCAL_PATH") bytes)"
fi

# If device not provided, prompt now (wait for user input)
if [[ -z "$DEVICE" ]]; then
	echo
	echo "Image is ready at: $LOCAL_PATH"
	while true; do
		read -p "Enter target block device to flash (e.g. /dev/sdX) or 'abort' to cancel: " DEVICE
		if [[ "$DEVICE" == "abort" ]]; then
			echo "Aborted by user."
			exit 1
		fi
		if [[ -b "$DEVICE" ]]; then
			break
		fi
		echo "$DEVICE not found or not a block device. Try again."
	done
fi

# Unmount any mounted partitions on the target device
echo "Unmounting any mounted partitions on $DEVICE"
MAP_PARTS=$(lsblk -ln -o NAME,MOUNTPOINT "$DEVICE" | awk '$2!="" {print $1}') || true
if [[ -n "$MAP_PARTS" ]]; then
	for p in $MAP_PARTS; do
		sudo umount "/dev/$p" || true
	done
fi

echo
echo "About to write $LOCAL_PATH to $DEVICE"
if [[ $ASSUME_YES -ne 1 ]]; then
	read -p "This will overwrite all data on $DEVICE. Proceed? (type 'yes' to continue) " CONF
	if [[ "$CONF" != "yes" ]]; then
		echo "Aborted by user."
		exit 1
	fi
fi

# Perform the flash. Support .bz2 compressed images (common for Yocto .wic.bz2)
if [[ "$LOCAL_PATH" == *.bz2 ]]; then
	echo "Flashing compressed .bz2 image to $DEVICE"
	if command -v pv >/dev/null 2>&1; then
		SIZE=$(stat -c%s "$LOCAL_PATH" || echo 0)
		pv -s "$SIZE" "$LOCAL_PATH" | bzcat | sudo dd of="$DEVICE" bs=4M status=progress conv=fsync
	else
		bzcat "$LOCAL_PATH" | sudo dd of="$DEVICE" bs=4M status=progress conv=fsync
	fi
else
	echo "Flashing raw image to $DEVICE"
	if command -v pv >/dev/null 2>&1; then
		pv "$LOCAL_PATH" | sudo dd of="$DEVICE" bs=4M status=progress conv=fsync
	else
		sudo dd if="$LOCAL_PATH" of="$DEVICE" bs=4M status=progress conv=fsync
	fi
fi

sudo sync
echo "Done. You may need to run 'sudo partprobe $DEVICE' or replug the SD card to see partitions."

exit 0
