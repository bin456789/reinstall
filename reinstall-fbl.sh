#!/usr/bin/env bash
# reinstall-freebsd-linux.sh
# Reinstall system on Linux / FreeBSD using DD + cloud-init (NoCloud) with:
#   - freebsd
#   - rocky
#   - almalinux
#   - fedora
#   - redhat
#
# All target systems use cloud-init to inject:
#   - root password (--password)
#   - SSH public key(s) (--ssh-key, multiple)
#   - SSH port (--ssh-port)
#   - optional FRPC config (--frpc-toml) stored as EFI:/nocloud/frpc.toml
#
# Requirements:
#   - Run with bash:  bash reinstall-freebsd-linux.sh ...
#   - Needs dd, xz, qemu-img, mount, and curl or wget or fetch
#   - Designed to be executed from a dracut initramfs (via rd.reinstall=1 wrapper).

set -eE

SCRIPT_NAME="${0##*/}"

error() {
    echo "ERROR: $*" >&2
    exit 1
}

warn() {
    echo "WARN: $*" >&2
}

info() {
    echo "==> $*"
}

usage() {
    cat <<EOF
Usage:
  $SCRIPT_NAME freebsd   14   [--disk /dev/sdX] [options...]
  $SCRIPT_NAME rocky     10   [--disk /dev/sdX] [options...]
  $SCRIPT_NAME almalinux 10   [--disk /dev/sdX] [options...]
  $SCRIPT_NAME fedora    43   [--disk /dev/sdX] [options...]
  $SCRIPT_NAME redhat         [--disk /dev/sdX] --img URL [options...]

If --disk is not specified, the script will try to auto-detect the main disk:
  - On Linux, picks the largest non-removable disk from lsblk.
  - On FreeBSD, picks the first non-cd disk from kern.disks.

Options:
  --disk DISK          Target disk, e.g. /dev/sda, /dev/vda, /dev/nvme0n1, /dev/ada0
                       If you omit /dev/, the script will automatically prefix /dev/.

  --img URL            Override default image URL (redhat requires this).
                       Supports http:// and https://

  --password PASSWORD  Set root password.
                       When using --ssh-key only, password can be empty (SSH key login only).

  --ssh-key KEY        Set SSH public key, can be specified multiple times. Supported forms:
                         --ssh-key "ssh-rsa AAAA... comment"
                         --ssh-key "ssh-ed25519 AAAA... comment"
                         --ssh-key "ecdsa-sha2-nistp256/384/521 AAAA... comment"
                         --ssh-key http://path/to/public_key
                         --ssh-key https://path/to/public_key
                         --ssh-key github:your_username
                         --ssh-key gitlab:your_username
                         --ssh-key /path/to/public_key
                         --ssh-key C:\\path\\to\\public_key   (not supported directly, copy to local file first)

  --ssh-port PORT      Change SSH port in the new system. cloud-init will try to modify
                       sshd_config and restart sshd. Default is 22 if not specified.

  --web-port PORT      Reserved for web log port. This script only writes it into cloud-init,
                       you can consume it later from within the system.

  --frpc-toml PATH/URL Add FRPC configuration for tunneling:
                         - Local path: copy to EFI:/nocloud/frpc.toml
                         - HTTP(S): download to EFI:/nocloud/frpc.toml
                       cloud-init will add a runcmd section that tries to copy this to /etc/frp
                       and start frpc if available.

  --hold 1             Only validate and print planned actions, do not download or write disk.
  --hold 2             Perform dd + NoCloud injection but do NOT reboot.

Password / SSH key behaviour:
  - If you specify one or more --ssh-key, you may omit --password (root login via key only).
  - If you specify --password, you may omit --ssh-key.
  - If you specify neither password nor ssh-key:
      * A random 20-character password (A–Z, a–z, 0–9) will be generated.
      * The generated password will be printed in the final summary.
  - Username is always: root
EOF
    exit 1
}

to_lower() {
    tr 'A-Z' 'a-z'
}

is_port_valid() {
    [[ "$1" =~ ^[0-9]+$ ]] && [ "$1" -ge 1 ] && [ "$1" -le 65535 ]
}

http_download() {
    local url="$1" dst="$2"
    if command -v curl >/dev/null 2>&1; then
        curl -L --fail -o "$dst" "$url"
    elif command -v wget >/dev/null 2>&1; then
        wget -O "$dst" "$url"
    elif command -v fetch >/dev/null 2>&1; then
        fetch -o "$dst" "$url"
    else
        error "No curl/wget/fetch found, cannot download: $url"
    fi
}

detect_os_arch() {
    OS=$(uname -s)
    ARCH=$(uname -m)

    case "$OS" in
        Linux|FreeBSD) ;;
        *) error "Unsupported OS: $OS (only Linux and FreeBSD are supported)" ;;
    esac

    case "$ARCH" in
        x86_64|amd64) MACHINE_ARCH="x86_64" ;;
        aarch64|arm64) MACHINE_ARCH="aarch64" ;;
        *)
            warn "Unknown arch: $ARCH, image URL selection may fail"
            MACHINE_ARCH="$ARCH"
            ;;
    esac
}

# -------- dependencies (只检查，不自动安装) --------

ensure_dependencies_linux_generic() {
    local missing=()

    if ! command -v qemu-img >/dev/null 2>&1; then
        missing+=("qemu-img")
    fi
    if ! command -v xz >/dev/null 2>&1; then
        missing+=("xz")
    fi
    if ! command -v curl >/dev/null 2>&1 && ! command -v wget >/dev/null 2>&1 && ! command -v fetch >/dev/null 2>&1; then
        missing+=("curl/wget/fetch")
    fi

    if [ "${#missing[@]}" -gt 0 ]; then
        error "Missing dependencies on Linux: ${missing[*]}
Please install them manually with your package manager (e.g. apt, zypper, pacman) and rerun this script."
    fi
}

ensure_dependencies_freebsd() {
    local missing=()

    if ! command -v qemu-img >/dev/null 2>&1; then
        missing+=("qemu-img (qemu-tools)")
    fi
    if ! command -v xz >/dev/null 2>&1; then
        missing+=("xz")
    fi
    if ! command -v curl >/dev/null 2>&1 && ! command -v wget >/dev/null 2>&1 && ! command -v fetch >/dev/null 2>&1; then
        missing+=("curl/wget/fetch")
    fi

    if [ "${#missing[@]}" -gt 0 ]; then
        error "Missing dependencies on FreeBSD: ${missing[*]}
Hint: you can install them with:
  pkg install qemu-tools xz curl"
    fi
}

ensure_dependencies() {
    if [ "$OS" = "Linux" ]; then
        ensure_dependencies_linux_generic
    elif [ "$OS" = "FreeBSD" ]; then
        ensure_dependencies_freebsd
    fi
}

auto_detect_disk() {
    info "Auto-detecting target disk..."

    if [[ "$OS" == "Linux" ]]; then
        if command -v lsblk >/dev/null 2>&1; then
            local best_name="" best_size=0
            while read -r name type rm size; do
                [ "$type" = "disk" ] || continue
                [ "$rm" = "0" ] || continue
                if [ "$size" -gt "$best_size" ]; then
                    best_size="$size"
                    best_name="$name"
                fi
            done < <(lsblk -b -ndo NAME,TYPE,RM,SIZE 2>/dev/null || true)

            if [ -n "$best_name" ]; then
                DISK="/dev/$best_name"
                info "Auto-detected disk: $DISK (largest non-removable disk)"
                return 0
            fi
        fi
        error "Unable to auto-detect target disk on Linux. Please specify --disk explicitly."
    else
        if command -v sysctl >/dev/null 2>&1; then
            local disks
            disks=$(sysctl -n kern.disks 2>/dev/null || true)
            for d in $disks; do
                case "$d" in
                    cd*|md*|lo*|ram*) continue ;;
                esac
                DISK="/dev/$d"
                info "Auto-detected disk: $DISK (from kern.disks)"
                return 0
            done
        fi
        error "Unable to auto-detect target disk on FreeBSD. Please specify --disk explicitly."
    fi
}

show_partition_info() {
    echo
    echo "---------------- Disk partition layout ----------------"
    if [ "$OS" = "Linux" ]; then
        if command -v lsblk >/dev/null 2>&1; then
            lsblk "$DISK" || true
        elif command -v fdisk >/dev/null 2>&1; then
            fdisk -l "$DISK" || true
        else
            echo "Could not show partition info (no lsblk/fdisk)."
        fi
    else
        if command -v gpart >/dev/null 2>&1; then
            local d="${DISK#/dev/}"
            gpart show "$d" 2>/dev/null || gpart show "$DISK" 2>/dev/null || echo "Could not show partition info with gpart."
        else
            echo "Could not show partition info (no gpart)."
        fi
    fi
    echo "-------------------------------------------------------"
}

# 可选 RHEL hook（不影响 initramfs 自动重装）
run_rhel_freebsd_hook() {
    if [ "$OS" = "Linux" ] && [ -f /etc/redhat-release ]; then
        if [ -f "./reinstall-fbll.sh" ]; then
            info "RHEL detected, running: bash reinstall-fbll.sh freebsd 14"
            if ! bash ./reinstall-fbll.sh freebsd 14; then
                warn "reinstall-fbll.sh freebsd 14 failed, continuing anyway."
            fi
        else
            warn "RHEL detected, but ./reinstall-fbll.sh not found; skipping RHEL hook."
        fi
    fi
}

parse_ssh_key() {
    local val="$1"
    local val_lower key_url tmpfile ssh_key

    ssh_key_error_and_exit() {
        error "$1
Available options:
  --ssh-key \"ssh-rsa ...\"
  --ssh-key \"ssh-ed25519 ...\"
  --ssh-key \"ecdsa-sha2-nistp256/384/521 ...\"
  --ssh-key github:your_username
  --ssh-key gitlab:your_username
  --ssh-key http://path/to/public_key
  --ssh-key https://path/to/public_key
  --ssh-key /path/to/public_key
  --ssh-key C:\\path\\to\\public_key (not supported directly, copy to a local path first)"
    }

    is_valid_ssh_key() {
        grep -qE '^(ecdsa-sha2-nistp(256|384|521)|ssh-(ed25519|rsa)) ' <<<"$1"
    }

    val_lower=$(to_lower <<<"$val")

    case "$val_lower" in
        github:*|gitlab:*|http://*|https://*)
            if [[ "$val_lower" == http* ]]; then
                key_url="$val"
            else
                IFS=: read -r site user <<<"$val"
                [ -n "$user" ] || ssh_key_error_and_exit "Need a username for $site"
                key_url="https://$site.com/$user.keys"
            fi
            info "Downloading SSH key from: $key_url"
            tmpfile=$(mktemp /tmp/reinstall-sshkey.XXXXXX)
            if ! http_download "$key_url" "$tmpfile"; then
                rm -f "$tmpfile"
                ssh_key_error_and_exit "Failed to download SSH key from $key_url"
            fi
            ssh_key=$(grep -m1 -E '^(ecdsa-sha2-nistp(256|384|521)|ssh-(ed25519|rsa)) ' "$tmpfile" || true)
            rm -f "$tmpfile"
            [ -n "$ssh_key" ] || ssh_key_error_and_exit "No valid SSH key found in $key_url"
            ;;
        *)
            if [[ "$val" =~ ^[A-Za-z]:\\ ]]; then
                ssh_key_error_and_exit "Windows path is not supported, please copy the key file to local filesystem and use /path/to/public_key"
            fi
            if is_valid_ssh_key "$val"; then
                ssh_key="$val"
            else
                if [ ! -f "$val" ]; then
                    ssh_key_error_and_exit "SSH key/file/url \"$val\" is invalid (file not found)"
                fi
                ssh_key=$(grep -m1 -E '^(ecdsa-sha2-nistp(256|384|521)|ssh-(ed25519|rsa)) ' "$val" || true)
                [ -n "$ssh_key" ] || ssh_key_error_and_exit "No valid SSH key found in file: $val"
            fi
            ;;
    esac

    echo "$ssh_key"
}

get_default_image_url() {
    local os="$1" ver="$2"

    case "$os" in
        freebsd)
            case "$ver" in
                14|14.*)
                    case "$MACHINE_ARCH" in
                        x86_64)
                            echo "https://download.freebsd.org/releases/VM-IMAGES/14.3-RELEASE/amd64/Latest/FreeBSD-14.3-RELEASE-amd64-BASIC-CLOUDINIT-ufs.qcow2.xz"
                            ;;
                        aarch64)
                            echo "https://download.freebsd.org/releases/VM-IMAGES/14.3-RELEASE/aarch64/Latest/FreeBSD-14.3-RELEASE-arm64-aarch64-BASIC-CLOUDINIT-ufs.qcow2.xz"
                            ;;
                        *)
                            error "Current arch $MACHINE_ARCH is not supported for automatic FreeBSD image selection, please specify --img manually"
                            ;;
                    esac
                    ;;
                *)
                    error "Unsupported FreeBSD version: $ver (only 14.x is baked in; use --img for others)"
                    ;;
            esac
            ;;
        rocky)
            case "$ver" in
                10)
                    case "$MACHINE_ARCH" in
                        x86_64)
                            echo "https://download.rockylinux.org/pub/rocky/10/images/x86_64/Rocky-10-EC2-LVM.latest.x86_64.qcow2"
                            ;;
                        *)
                            error "Rocky 10 default image is only provided for x86_64; use --img for other arches"
                            ;;
                    esac
                    ;;
                *)
                    error "Unsupported Rocky version: $ver (future: add rocky 9, etc.)"
                    ;;
            esac
            ;;
        almalinux)
            case "$ver" in
                10)
                    case "$MACHINE_ARCH" in
                        x86_64)
                            echo "https://repo.almalinux.org/almalinux/10/cloud/x86_64/images/AlmaLinux-10-GenericCloud-latest.x86_64.qcow2"
                            ;;
                        aarch64)
                            echo "https://repo.almalinux.org/almalinux/10/cloud/aarch64/images/AlmaLinux-10-GenericCloud-latest.aarch64.qcow2"
                            ;;
                        *)
                            error "Current arch $MACHINE_ARCH is not supported for automatic AlmaLinux image selection, please specify --img manually"
                            ;;
                    esac
                    ;;
                *)
                    error "Unsupported AlmaLinux version: $ver"
                    ;;
            esac
            ;;
        fedora)
            case "$ver" in
                43)
                    case "$MACHINE_ARCH" in
                        x86_64)
                            echo "https://download.fedoraproject.org/pub/fedora/linux/releases/43/Cloud/x86_64/images/Fedora-Cloud-Base-Generic-43-1.6.x86_64.qcow2"
                            ;;
                        aarch64)
                            echo "https://download.fedoraproject.org/pub/fedora/linux/releases/43/Cloud/aarch64/images/Fedora-Cloud-Base-Generic-43-1.6.aarch64.qcow2"
                            ;;
                        *)
                            error "Current arch $MACHINE_ARCH is not supported for automatic Fedora image selection, please specify --img manually"
                            ;;
                    esac
                    ;;
                *)
                    error "Unsupported Fedora version: $ver"
                    ;;
            esac
            ;;
        redhat)
            echo ""
            ;;
        *)
            error "Unknown target OS: $os"
            ;;
    esac
}

find_efi_partition() {
    local disk="$1" part
    case "$disk" in
        */nvme*|*/*nvd*)
            part="${disk}p1"
            ;;
        *)
            if [[ "$(uname -s)" == "FreeBSD" ]]; then
                part="${disk}p1"
            else
                part="${disk}1"
            fi
            ;;
    esac
    echo "$part"
}

write_nocloud_seed() {
    local os="$1" meta_path="$2" user_path="$3"

    mkdir -p "$(dirname "$meta_path")"

    cat >"$meta_path" <<EOF
instance-id: iid-$(date +%s)
local-hostname: $os
EOF

    {
        echo "#cloud-config"

        if [ -n "$PASSWORD" ]; then
            cat <<EOF
ssh_pwauth: true
disable_root: false
chpasswd:
  list: |
    root:${PASSWORD}
  expire: false
EOF
        fi

        if [ -n "$SSH_KEYS_ALL" ]; then
            echo "ssh_authorized_keys:"
            while IFS= read -r line; do
                [ -n "$line" ] || continue
                printf '  - %s\n' "$line"
            done <<<"$SSH_KEYS_ALL"
        fi

        if [ -n "$WEB_PORT" ]; then
            cat <<EOF

write_files:
  - path: /etc/reinstall-web-port
    permissions: '0644'
    owner: root:root
    content: |
      $WEB_PORT
EOF
        fi

        if [ -n "$SSH_PORT" ] || [ -n "$FRPC_PRESENT" ]; then
            echo
            echo "runcmd:"
        fi

        if [ -n "$SSH_PORT" ]; then
            cat <<EOF
  - |
      # Try to change SSH port on Linux / FreeBSD
      if [ -f /etc/ssh/sshd_config ]; then
        sed -i 's/^#Port .*/Port ${SSH_PORT}/' /etc/ssh/sshd_config 2>/dev/null || \
        sed -i 's/^Port .*/Port ${SSH_PORT}/' /etc/ssh/sshd_config 2>/dev/null || \
        sed -i '' 's/^#Port .*/Port ${SSH_PORT}/' /etc/ssh/sshd_config 2>/dev/null || \
        sed -i '' 's/^Port .*/Port ${SSH_PORT}/' /etc/ssh/sshd_config 2>/dev/null || true
      fi
      service sshd restart 2>/dev/null || systemctl restart sshd 2>/dev/null || true
EOF
        fi

        if [ -n "$FRPC_PRESENT" ]; then
            cat <<'EOF'
  - |
      # If EFI nocloud contains frpc.toml, copy to /etc/frp and try to start frpc
      if [ -f /boot/efi/nocloud/frpc.toml ]; then
        mkdir -p /etc/frp
        cp /boot/efi/nocloud/frpc.toml /etc/frp/frpc.toml
        (frpc -c /etc/frp/frpc.toml || /usr/local/bin/frpc -c /etc/frp/frpc.toml || true) &
      fi
EOF
        fi
    } >"$user_path"
}

# ----------------- main -----------------

[ $# -lt 1 ] && usage

TARGET_OS=$(echo "$1" | to_lower)
shift || true

TARGET_VER=""
IMG_URL=""
DISK=""
PASSWORD=""
SSH_KEYS_ALL=""
SSH_PORT=""
WEB_PORT=""
FRPC_TOML=""
FRPC_PRESENT=""
HOLD="0"
AUTO_PASSWORD=0

if [ $# -gt 0 ] && [[ "$1" =~ ^[0-9]+$ ]]; then
    case "$TARGET_OS" in
        freebsd|rocky|almalinux|fedora)
            TARGET_VER="$1"
            shift
            ;;
        redhat)
            error "Do not specify a version for redhat. Use: $SCRIPT_NAME redhat --img URL [--disk /dev/XXX] ..."
            ;;
        *)
            ;;
    esac
fi

while [ $# -gt 0 ]; do
    case "$1" in
        -h|--help)
            usage
            ;;
        --disk)
            shift
            [ -n "$1" ] || error "Need value for --disk"
            DISK="$1"
            ;;
        --disk=*)
            DISK="${1#*=}"
            ;;
        --img)
            shift
            [ -n "$1" ] || error "Need value for --img"
            IMG_URL="$1"
            ;;
        --img=*)
            IMG_URL="${1#*=}"
            ;;
        --password|--passwd)
            shift
            [ -n "$1" ] || error "Need value for --password"
            PASSWORD="$1"
            ;;
        --ssh-key|--public-key)
            shift
            [ -n "$1" ] || error "Need value for --ssh-key"
            key_line=$(parse_ssh_key "$1")
            if [ -n "$SSH_KEYS_ALL" ]; then
                SSH_KEYS_ALL+=$'\n'
            fi
            SSH_KEYS_ALL+="$key_line"
            ;;
        --ssh-port)
            shift
            [ -n "$1" ] || error "Need value for --ssh-port"
            is_port_valid "$1" || error "Invalid --ssh-port: $1"
            SSH_PORT="$1"
            ;;
        --web-port)
            shift
            [ -n "$1" ] || error "Need value for --web-port"
            is_port_valid "$1" || error "Invalid --web-port: $1"
            WEB_PORT="$1"
            ;;
        --frpc-toml)
            shift
            [ -n "$1" ] || error "Need value for --frpc-toml"
            FRPC_TOML="$1"
            ;;
        --hold)
            shift
            [ -n "$1" ] || error "Need value for --hold"
            [[ "$1" == "1" || "$1" == "2" ]] || error "Invalid --hold: $1 (must be 1 or 2)"
            HOLD="$1"
            ;;
        *)
            error "Unknown argument: $1"
            ;;
    esac
    shift || true
done

detect_os_arch
ensure_dependencies  # no auto-install, just verify deps

if [ -n "$DISK" ]; then
    if [[ "$DISK" != /dev/* ]]; then
        DISK="/dev/$DISK"
    fi
else
    auto_detect_disk
fi

if [ ! -b "$DISK" ] && [ ! -c "$DISK" ]; then
    error "Target disk $DISK does not exist or is not a block/char device"
fi

# 密码 / SSH：完全无人值守模式
# 如果既没有 --password 也没有 --ssh-key，就自动生成随机密码，不提示。
if [ -z "$PASSWORD" ] && [ -z "$SSH_KEYS_ALL" ]; then
    if command -v tr >/dev/null 2>&1; then
        PASSWORD=$(LC_ALL=C tr -dc 'A-Za-z0-9' </dev/urandom | head -c 20 || true)
    fi
    if [ -z "$PASSWORD" ]; then
        error "Failed to generate random password."
    fi
    AUTO_PASSWORD=1
    info "No --password or --ssh-key specified; generated random root password (will be shown in final summary)."
fi

if [ -z "$TARGET_VER" ]; then
    case "$TARGET_OS" in
        freebsd)   TARGET_VER="14" ;;
        rocky)     TARGET_VER="10" ;;
        almalinux) TARGET_VER="10" ;;
        fedora)    TARGET_VER="43" ;;
        redhat)    TARGET_VER="" ;;
        *)         ;;
    esac
fi

if [ -z "$IMG_URL" ]; then
    IMG_URL=$(get_default_image_url("$TARGET_OS" "$TARGET_VER"))
    # shellcheck disable=SC2016
    if [ -z "$IMG_URL" ] && [ "$TARGET_OS" = "redhat" ]; then
        error "For redhat you must specify image URL with --img"
    fi
fi

info "Host: OS=$OS ARCH=$ARCH ($MACHINE_ARCH)"
info "Target: $TARGET_OS ${TARGET_VER:-"(no version)"}"
info "Disk: $DISK"
info "Image URL: $IMG_URL"

if [ "$HOLD" = "1" ]; then
    info "--hold 1 is set: only parameter check and summary, no download or disk write."
    exit 0
fi

TMPDIR=$(mktemp -d /tmp/reinstall-cloudinit.XXXXXX)
trap 'rm -rf "$TMPDIR"' EXIT

IMG_QCOW="$TMPDIR/image.qcow2"
IMG_RAW="$TMPDIR/image.raw"

info "Downloading image..."
http_download "$IMG_URL" "$IMG_QCOW"

if file "$IMG_QCOW" | grep -qi 'xz compressed'; then
    info "Detected xz compressed image, decompressing (progress may be shown)..."
    mv "$IMG_QCOW" "$IMG_QCOW.xz"
    if command -v pv >/dev/null 2>&1; then
        xz -dc "$IMG_QCOW.xz" | pv >"$IMG_QCOW"
    else
        xz -dc "$IMG_QCOW.xz" >"$IMG_QCOW"
    fi
fi

info "Converting qcow2 to raw with qemu-img (with progress)..."
qemu-img convert -p -O raw "$IMG_QCOW" "$IMG_RAW"

echo
echo "WARNING: dd will be run on $DISK. ALL DATA ON THIS DISK WILL BE LOST!"
info "Initramfs/unattended mode: no interactive confirmation, proceeding automatically."

info "Writing image to disk with dd, this may take a while..."
dd if="$IMG_RAW" of="$DISK" bs=4M conv=fsync status=progress
sync
info "dd finished."

if command -v partprobe >/dev/null 2>&1; then
    partprobe "$DISK" || true
elif command -v blockdev >/dev/null 2>&1; then
    blockdev --rereadpt "$DISK" || true
fi

sleep 2

EFI_PART=$(find_efi_partition "$DISK")
info "Trying EFI partition: $EFI_PART"

MNT_EFI="$TMPDIR/efi"
mkdir -p "$MNT_EFI"

if [[ "$OS" == "FreeBSD" ]]; then
    if ! mount -t msdosfs "$EFI_PART" "$MNT_EFI" 2>/dev/null; then
        warn "Failed to mount EFI partition $EFI_PART, skipping cloud-init NoCloud injection."
        EFI_PART=""
    fi
else
    if ! mount "$EFI_PART" "$MNT_EFI" 2>/dev/null; then
        if ! mount -t vfat "$EFI_PART" "$MNT_EFI" 2>/dev/null && ! mount -t msdos "$EFI_PART" "$MNT_EFI" 2>/dev/null; then
            warn "Failed to mount EFI partition $EFI_PART, skipping cloud-init NoCloud injection."
            EFI_PART=""
        fi
    fi
fi

if [ -n "$EFI_PART" ]; then
    NOCLOUD_DIR="$MNT_EFI/nocloud"
    mkdir -p "$NOCLOUD_DIR"

    if [ -n "$FRPC_TOML" ]; then
        FRPC_PRESENT=1
        if [[ "$FRPC_TOML" =~ ^https?:// ]]; then
            info "Downloading FRPC config: $FRPC_TOML"
            if ! http_download "$FRPC_TOML" "$NOCLOUD_DIR/frpc.toml"; then
                warn "Failed to download FRPC config, ignoring"
                FRPC_PRESENT=""
            fi
        elif [ -f "$FRPC_TOML" ]; then
            info "Copying FRPC config from: $FRPC_TOML"
            cp "$FRPC_TOML" "$NOCLOUD_DIR/frpc.toml"
        else
            warn "Invalid FRPC config path: $FRPC_TOML, ignoring"
            FRPC_PRESENT=""
        fi
    fi

    info "Writing NoCloud seed to EFI:/nocloud/ ..."
    write_nocloud_seed "$TARGET_OS" "$NOCLOUD_DIR/meta-data" "$NOCLOUD_DIR/user-data"

    sync
    umount "$MNT_EFI" || true
else
    warn "EFI could not be mounted; target system can still boot, but cloud-init configuration may not be applied."
fi

info "Image write and cloud-init NoCloud injection completed."

run_rhel_freebsd_hook
show_partition_info

FINAL_SSH_PORT="${SSH_PORT:-22}"

echo
echo "==================== Installation summary ===================="
echo "Disk device:  $DISK"
echo "Target OS:    $TARGET_OS ${TARGET_VER:-"(no version)"}"
echo "Username:     root"
echo "SSH port:     $FINAL_SSH_PORT"

if [ -n "$PASSWORD" ]; then
    echo "Root password:"
    echo "  $PASSWORD"
else
    echo "Root password: (not set; SSH key login only)"
fi

echo "SSH authorized keys:"
if [ -n "$SSH_KEYS_ALL" ]; then
    while IFS= read -r k; do
        [ -n "$k" ] && echo "  $k"
    done <<<"$SSH_KEYS_ALL"
else
    echo "  (none)"
fi

if [ "$AUTO_PASSWORD" -eq 1 ]; then
    echo
    echo "NOTE: The above root password was auto-generated."
fi
echo "=============================================================="

if [ "$HOLD" = "2" ]; then
    info "--hold 2 is set: will NOT reboot automatically. You can inspect or chroot into the new system manually."
    exit 0
fi

echo
echo "You can now reboot into the new system, for example:"
if [ "$OS" = "FreeBSD" ]; then
    echo "  shutdown -r now"
else
    echo "  reboot"
fi

exit 0
