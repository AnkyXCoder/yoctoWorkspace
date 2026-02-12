#!/usr/bin/env bash
set -euo pipefail

REMOTE=""
REMOTE_HOST=""
REMOTE_REL=""
DEVICE=""
LOCAL_DIR=""
ASSUME_YES=0
FORCE_LOCAL_FILE=""
# Download type: 'bz2', 'bmap', or empty for both/default
DOWNLOAD_TYPE=""
# Flash method preference: 'bmap' (default) or 'dd'
FLASH_METHOD="bmap"

# directories and timestamps
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
WORKSPACE_DIR=$(cd "$SCRIPT_DIR/.." && pwd)
IMAGES_DIR="$WORKSPACE_DIR/images"
DRY_RUN=0
ORIG_ARGS=("$@")

# support long form --dry-run by removing it before getopts runs
NEW_ARGS=()
for a in "$@"; do
	if [[ "$a" == "--dry-run" ]]; then
		DRY_RUN=1
	else
		NEW_ARGS+=("$a")
	fi
done
set -- "${NEW_ARGS[@]}"
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
	-t <type>      Download type: 'bz2' (bz2+related), 'bmap' (bmap+related). If omitted, downloads both sets.
	-m <method>    Flash method preference: 'bmap' (default) or 'dd'
	-y             Skip interactive confirmation prompts (use with caution)
	-h             Show this help

Behavior notes:
	- Downloaded or copied images are placed in: <workspace>/images/<timestamp>/
	- The script will attempt to detect YOCTO_MACHINE from \$(yocto-env.sh) and build
		the standard path from the remote build dir: <build>/tmp/deploy/images/<MACHINE>/core-image-base-<MACHINE>.rootfs.wic.bz2
	- If you provide -H and -p, the remote path is constructed from the supplied
		build directory.
	- If you provide -H and -p, the remote path is constructed from the supplied
		build directory. The script will attempt to download the primary image
		(e.g. .bz2) and any companion mapping files (.bmap or .bzmap) when
		available to enable faster flashing with bmaptool.

Examples:
	# construct path from remote build directory and flash (interactive device prompt allowed)
	./scripts/$(basename "$0") -H user@host -p /home/user/yoctoWorkspace/build

	# use a pre-downloaded file and prompt for device
	./scripts/$(basename "$0") -F /tmp/core-image-base-raspberrypi4.rootfs.wic.bz2

	# non-interactive: download from remote and write to /dev/sdb (DANGEROUS)
	sudo ./scripts/$(basename "$0") -r user@host:/home/user/yoctoWorkspace/build/tmp/deploy/images/raspberrypi4/core-image-base-raspberrypi4.rootfs.wic.bz2 -d /dev/sdb -y

	# download and keep images in custom storage dir (remote build dir provided)
	./scripts/$(basename "$0") -H user@host -p /home/user/yoctoWorkspace/build -l /tmp/my_images

	# Construct path from remote build dir and download image + mapping files (default)
	./scripts/$(basename "$0") -H user@host -p /home/user/yoctoWorkspace/build -d /dev/sdX

	# Only download .bmap (and companion files) and flash using bmap where possible
	./scripts/$(basename "$0") -H user@host -p /home/user/yoctoWorkspace/build -t bmap -m bmap -d /dev/sdX

	# Only download .bz2 images and related artifacts and force dd flashing
	./scripts/$(basename "$0") -H user@host -p /home/user/yoctoWorkspace/build -t bz2 -m dd -d /dev/sdX

EOF
}

while getopts ":r:H:p:d:l:F:nt:m:yh" opt; do
	case ${opt} in
	r) REMOTE="$OPTARG" ;;
	H) REMOTE_HOST="$OPTARG" ;;
	p) REMOTE_REL="$OPTARG" ;;
	d) DEVICE="$OPTARG" ;;
	l) LOCAL_DIR="$OPTARG" ;;
	F) FORCE_LOCAL_FILE="$OPTARG" ;;
	t) DOWNLOAD_TYPE="$OPTARG" ;;
	n) DRY_RUN=1 ;;
	m) FLASH_METHOD="$OPTARG" ;;
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

	# Build list of remote files to fetch: primary file plus companion .bmap if present.
	REMOTE_FILES=()
	# If the REMOTE was a specific file, include it first
	if [[ "$RESOLVED_REMOTE" == *:* ]]; then
		REMOTE_FILES+=("$RESOLVED_REMOTE")
	fi

	# If REMOTE contains host:path, attempt to probe companion files on remote host
	if [[ "$RESOLVED_REMOTE" == *:* ]]; then
		REMOTE_HOST_ONLY="${RESOLVED_REMOTE%%:*}"
		REMOTE_PATH_ONLY="${RESOLVED_REMOTE#*:}"
		REMOTE_DIR_ONLY=$(ssh -o BatchMode=yes -o ConnectTimeout=10 "$REMOTE_HOST_ONLY" "dirname -- '$REMOTE_PATH_ONLY'" 2>/dev/null || true)
		if [[ -z "$REMOTE_DIR_ONLY" ]]; then
			REMOTE_DIR_ONLY=$(dirname "$REMOTE_PATH_ONLY")
		fi

		# helper: expand remote glob and add existing files to REMOTE_FILES
		remote_add_pattern() {
			local pattern="$1"
			local list
			list=$(ssh -o BatchMode=yes -o ConnectTimeout=10 "$REMOTE_HOST_ONLY" "ls -1 ${pattern} 2>/dev/null || true" 2>/dev/null || true)
			if [[ -n "$list" ]]; then
				while IFS= read -r f; do
					# skip empty lines
					[[ -z "$f" ]] && continue
					REMOTE_FILES+=("${REMOTE_HOST_ONLY}:${f}")
				done <<<"$list"
			fi
		}

		# build candidate patterns based on requested download type
		case "$DOWNLOAD_TYPE" in
		bz2)
			PATTERNS=("${REMOTE_DIR_ONLY}/*.wic.bz2" "${REMOTE_DIR_ONLY}/*.wic" "${REMOTE_DIR_ONLY}/core-image-base-${MACHINE}.rootfs*.ext3" "${REMOTE_DIR_ONLY}/core-image-base-${MACHINE}.rootfs*.tar.bz2" "${REMOTE_DIR_ONLY}/core-image-base*manifest" "${REMOTE_DIR_ONLY}/core-image-base.env")
			;;
		bmap)
			PATTERNS=("${REMOTE_DIR_ONLY}/*.wic.bmap" "${REMOTE_DIR_ONLY}/*.wic" "${REMOTE_DIR_ONLY}/*.wic.bz2" "${REMOTE_DIR_ONLY}/core-image-base*manifest" "${REMOTE_DIR_ONLY}/core-image-base.env")
			;;
		*)
			PATTERNS=("${REMOTE_DIR_ONLY}/*.wic" "${REMOTE_DIR_ONLY}/*.wic.bz2" "${REMOTE_DIR_ONLY}/*.wic.bmap" "${REMOTE_DIR_ONLY}/*.wic.bzmap" "${REMOTE_DIR_ONLY}/core-image-base-${MACHINE}.rootfs*.ext3" "${REMOTE_DIR_ONLY}/core-image-base-${MACHINE}.rootfs*.tar.bz2" "${REMOTE_DIR_ONLY}/core-image-base*manifest" "${REMOTE_DIR_ONLY}/core-image-base.env")
			;;
		esac

		for pat in "${PATTERNS[@]}"; do
			remote_add_pattern "$pat"
		done

	fi

	DOWNLOAD_OK=0
	# Try rsync for all discovered remote files at once
	if [[ $DRY_RUN -eq 1 ]]; then
		echo "Dry-run: remote files that would be downloaded:"
		if [[ ${#REMOTE_FILES[@]} -eq 0 ]]; then
			echo "  (no files discovered)"
		else
			for f in "${REMOTE_FILES[@]}"; do
				echo "  $f"
			done
		fi
		exit 0
	fi

	if command -v rsync >/dev/null 2>&1; then
		if [[ ${#REMOTE_FILES[@]} -eq 0 ]]; then
			echo "No remote files discovered to fetch." >&2
		else
			echo "Attempting rsync for:"
			for f in "${REMOTE_FILES[@]}"; do echo "  $f"; done
			RSYNC_CMD=(rsync -avPL --partial "${REMOTE_FILES[@]}" "$TARGET_DIR/")
			echo "Running: ${RSYNC_CMD[*]}"
			if "${RSYNC_CMD[@]}"; then
				DOWNLOAD_OK=1
			else
				echo "rsync failed, will try scp fallback" >&2
			fi
		fi
	fi

	if [[ $DOWNLOAD_OK -eq 0 ]]; then
		echo "Attempting scp for each file..."
		SCP_FAILED=0
		for src in "${REMOTE_FILES[@]}"; do
			echo "scp $src -> $TARGET_DIR/"
			if ! scp "$src" "$TARGET_DIR/"; then
				SCP_FAILED=1
				echo "scp failed for $src" >&2
			fi
		done
		if [[ $SCP_FAILED -eq 0 ]]; then
			DOWNLOAD_OK=1
		fi
	fi

	# If no download method succeeded, fail early and do not proceed to flashing.
	if [[ $DOWNLOAD_OK -eq 0 ]]; then
		echo "Error: all download methods failed for $RESOLVED_REMOTE" >&2
		exit 4
	fi

	# Print files downloaded into target dir
	echo
	echo "Downloaded files:"
	ls -1 "$TARGET_DIR" || true

	# Determine available WIC-related files (prefer to flash .wic with .bmap when possible)
	WIC_FILE=$(ls -1 "$TARGET_DIR"/*.wic 2>/dev/null | head -n1 || true)
	WIC_BZ2_FILE=$(ls -1 "$TARGET_DIR"/*.wic.bz2 2>/dev/null | head -n1 || true)
	WIC_BMAP_FILE=$(ls -1 "$TARGET_DIR"/*.wic.bmap 2>/dev/null | head -n1 || true)

	# If user provided a specific path earlier, prefer that basename when it exists
	if [[ -n "${RESOLVED_REMOTE:-}" && "${RESOLVED_REMOTE}" == *:* ]]; then
		EXPECTED_BASENAME=$(basename -- "$RESOLVED_REMOTE")
		if [[ -f "$TARGET_DIR/$EXPECTED_BASENAME" ]]; then
			LOCAL_PATH="$TARGET_DIR/$EXPECTED_BASENAME"
		fi
	fi

	# Select preferred image according to availability and requested download type
	if [[ -n "$WIC_BMAP_FILE" && "$FLASH_METHOD" != "dd" ]]; then
		# prefer uncompressed .wic when bmap present
		if [[ -n "$WIC_FILE" ]]; then
			LOCAL_PATH="$WIC_FILE"
		elif [[ -n "$WIC_BZ2_FILE" ]]; then
			LOCAL_PATH="$WIC_BZ2_FILE"
		fi
	fi

	if [[ -z "${LOCAL_PATH:-}" ]]; then
		# fallback selection based on presence
		if [[ -n "$WIC_BZ2_FILE" ]]; then
			LOCAL_PATH="$WIC_BZ2_FILE"
		elif [[ -n "$WIC_FILE" ]]; then
			LOCAL_PATH="$WIC_FILE"
		else
			# try to pick a likely image file from TARGET_DIR (e.g. rootfs images)
			NEWEST=$(ls -t "$TARGET_DIR"/* 2>/dev/null | grep -E "(\.wic(\.bz2)?|\.img(\.bz2)?|rootfs.*\.ext3|rootfs.*\.tar\.bz2)" | head -n1 || true)
			if [[ -n "$NEWEST" && -f "$NEWEST" ]]; then
				LOCAL_PATH="$NEWEST"
				echo "Selected image for flashing: $LOCAL_PATH"
			else
				echo "Error: no suitable image found in $TARGET_DIR" >&2
				exit 4
			fi
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

# Determine image type and flash accordingly. Support:
# - bmap (use bmaptool when available)
# - compressed .bz2 images (use bmaptool if .bmap present, otherwise bzcat|dd)
# - raw images (dd)

flash_with_dd() {
	local src="$1"
	if command -v pv >/dev/null 2>&1; then
		pv "$src" | sudo dd of="$DEVICE" bs=4M status=progress conv=fsync
	else
		sudo dd if="$src" of="$DEVICE" bs=4M status=progress conv=fsync
	fi
}

flash_bz2_with_dd() {
	local src="$1"
	if command -v pv >/dev/null 2>&1; then
		SIZE=$(stat -c%s "$src" || echo 0)
		pv -s "$SIZE" "$src" | bzcat | sudo dd of="$DEVICE" bs=4M status=progress conv=fsync
	else
		bzcat "$src" | sudo dd of="$DEVICE" bs=4M status=progress conv=fsync
	fi
}

# helper: try to find a companion .bmap file for a given image path
find_bmap_for() {
	local img="$1"
	local base="${img%.*}"
	# check for .bmap and .bzmap siblings
	if [[ -f "${base}.bmap" ]]; then
		echo "${base}.bmap"
		return 0
	fi
	if [[ -f "${base}.bzmap" ]]; then
		echo "${base}.bzmap"
		return 0
	fi
	# if image ends with .bz2 try stripping .bz2 first and check again
	if [[ "$img" == *.bz2 ]]; then
		local stripped="${img%.bz2}"
		if [[ -f "${stripped}.bmap" ]]; then
			echo "${stripped}.bmap"
			return 0
		fi
		if [[ -f "${stripped}.bzmap" ]]; then
			echo "${stripped}.bzmap"
			return 0
		fi
	fi
	return 1
}

echo "Determining flashing method for: $LOCAL_PATH"

# If user provided a .bmap file directly
if [[ "$LOCAL_PATH" == *.bmap ]]; then
	BMAP_FILE="$LOCAL_PATH"
	# try to find image file candidates
	CANDIDATES=("${LOCAL_PATH%.bmap}.wic" "${LOCAL_PATH%.bmap}.wic.bz2" "${LOCAL_PATH%.bmap}.img" "${LOCAL_PATH%.bmap}.img.bz2" "${LOCAL_PATH%.bmap}.bz2")
	IMAGE_FILE=""
	for c in "${CANDIDATES[@]}"; do
		if [[ -f "$c" ]]; then
			IMAGE_FILE="$c"
			break
		fi
	done
	if [[ -z "$IMAGE_FILE" ]]; then
		echo "Error: could not find image file for bmap: $BMAP_FILE" >&2
		exit 5
	fi
	echo "Using bmap: $BMAP_FILE -> image: $IMAGE_FILE"
	if [[ "$FLASH_METHOD" == "dd" ]]; then
		echo "Flashing with dd (forced by -m dd)"
		if [[ "$IMAGE_FILE" == *.bz2 ]]; then
			flash_bz2_with_dd "$IMAGE_FILE"
		else
			flash_with_dd "$IMAGE_FILE"
		fi
	elif command -v bmaptool >/dev/null 2>&1; then
		echo "Writing with bmaptool copy $IMAGE_FILE $DEVICE --bmap $BMAP_FILE"
		sudo bmaptool copy "$IMAGE_FILE" "$DEVICE" --bmap "$BMAP_FILE"
	else
		echo "Warning: bmaptool not found; falling back to dd on the image file (may be slower)" >&2
		if [[ "$IMAGE_FILE" == *.bz2 ]]; then
			flash_bz2_with_dd "$IMAGE_FILE"
		else
			flash_with_dd "$IMAGE_FILE"
		fi
	fi

else
	# Not a .bmap path. Check for companion .bmap for this image
	POSSIBLE_BMAP=$(find_bmap_for "$LOCAL_PATH" || true)
	if [[ -n "$POSSIBLE_BMAP" && -f "$POSSIBLE_BMAP" ]]; then
		echo "Found companion bmap: $POSSIBLE_BMAP"
		if [[ "$FLASH_METHOD" == "dd" ]]; then
			echo "Flashing with dd (forced by -m dd)"
			if [[ "$LOCAL_PATH" == *.bz2 ]]; then
				flash_bz2_with_dd "$LOCAL_PATH"
			else
				flash_with_dd "$LOCAL_PATH"
			fi
		elif command -v bmaptool >/dev/null 2>&1; then
			echo "Writing with bmaptool copy $LOCAL_PATH $DEVICE --bmap $POSSIBLE_BMAP"
			sudo bmaptool copy "$LOCAL_PATH" "$DEVICE" --bmap "$POSSIBLE_BMAP"
		else
			echo "Warning: bmaptool not found; falling back to dd on the image file (may be slower)" >&2
			if [[ "$LOCAL_PATH" == *.bz2 ]]; then
				flash_bz2_with_dd "$LOCAL_PATH"
			else
				flash_with_dd "$LOCAL_PATH"
			fi
		fi
	else
		# No bmap available; handle compressed and raw images
		if [[ "$FLASH_METHOD" == "dd" ]]; then
			echo "Flashing with dd (forced by -m dd)"
			if [[ "$LOCAL_PATH" == *.bz2 ]]; then
				flash_bz2_with_dd "$LOCAL_PATH"
			else
				flash_with_dd "$LOCAL_PATH"
			fi
		else
			# No bmap available; handle compressed and raw images
			if [[ "$LOCAL_PATH" == *.bz2 ]]; then
				echo "No bmap found; flashing compressed .bz2 image to $DEVICE"
				flash_bz2_with_dd "$LOCAL_PATH"
			else
				echo "Flashing raw image to $DEVICE"
				flash_with_dd "$LOCAL_PATH"
			fi
		fi
	fi
fi

sudo sync
echo "Done. You may need to run 'sudo partprobe $DEVICE' or replug the SD card to see partitions."

exit 0
