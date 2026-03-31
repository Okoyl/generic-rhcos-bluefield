#!/bin/bash
#
# Build a BlueField Boot (BFB) image from RHCOS components.
#
set -euo pipefail

# ------------------------------------------------------------------------------
# Configuration
# ------------------------------------------------------------------------------

readonly SCRIPT_DIR="$(realpath "$(dirname "$0")")"
readonly WORKSPACE="${SCRIPT_DIR}/workspace"
readonly BOOTIMAGES_DIR="${WORKSPACE}/bootimages"
readonly BOOTIMAGES_URL="https://linux.mellanox.com/public/repo/doca/3.1.0/rhel9.6/arm64-dpu/mlxbf-bootimages-signed-4.12.0-13720.aarch64.rpm"

readonly IMG_BASE_NAME="rhcos"
readonly DATETIME="$(date +'%F_%H-%M')"

# Temp files for cleanup
TEMP_FILES=()

# ------------------------------------------------------------------------------
# Utilities
# ------------------------------------------------------------------------------

die() {
    echo "Error: $*" >&2
    exit 1
}

log() {
    echo "==> $*"
}

cleanup() {
    for f in "${TEMP_FILES[@]:-}"; do
        rm -f "$f"
    done
}
trap cleanup EXIT

make_temp() {
    local tmp
    tmp=$(mktemp)
    TEMP_FILES+=("$tmp")
    echo "$tmp"
}

# ------------------------------------------------------------------------------
# Usage
# ------------------------------------------------------------------------------

usage() {
    cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Build a BlueField Boot (BFB) image from RHCOS components.

Options:
  --kernel PATH         Path to kernel image
  --initramfs PATH      Path to initramfs image
  --rootfs PATH         Path to rootfs image
  --default-bfb PATH    Path to default.bfb file
  --capsule PATH        Path to capsule file
  --infojson PATH       Path to info.json manifest file
  --outfile PATH        Output BFB file path
  -h, --help            Show this help message

Environment Variables:
  RHCOS_VERSION         RHCOS version string (appended to image name)

If --default-bfb and --capsule are not provided, they will be extracted from the
bootimages RPM. These two options must be used together.
EOF
    exit 0
}

# ------------------------------------------------------------------------------
# Boot Images
# ------------------------------------------------------------------------------

ensure_bootimages() {
    if [[ -d "${BOOTIMAGES_DIR}" ]] && [[ -n "$(ls -A "${BOOTIMAGES_DIR}" 2>/dev/null)" ]]; then
        return 0
    fi

    log "Downloading bootimages..."
    mkdir -p "${BOOTIMAGES_DIR}"
    pushd "${BOOTIMAGES_DIR}" > /dev/null

    curl -fsSLO "${BOOTIMAGES_URL}"
    rpm2cpio mlxbf-bootimages-signed*.rpm | cpio -idm

    popd > /dev/null
}

# ------------------------------------------------------------------------------
# BFB Builder
# ------------------------------------------------------------------------------

build_bfb() {
    local initramfs_path="$1"
    local output_path="$2"
    local infojson_path="${3:-}"
    local kernel_path="${WORKSPACE}/kernel"
    local output_dir output_name

    output_dir="$(dirname "${output_path}")"
    output_name="$(basename "${output_path}")"

    mkdir -p "${output_dir}"

    # Create boot configuration files
    local boot_args_v0 boot_args_v2 boot_path boot_desc
    boot_args_v0=$(make_temp)
    boot_args_v2=$(make_temp)
    boot_path=$(make_temp)
    boot_desc=$(make_temp)

    # BF1 boot arguments
    printf "console=ttyAMA0 earlycon=pl011,0x01000000 earlycon=pl011,0x01800000 initrd=initramfs" \
        > "${boot_args_v0}"

    # BF2+ boot arguments
    local kernel_args="console=hvc0 console=ttyAMA0 earlycon=pl011,0x13010000"
    kernel_args+=" initrd=initramfs"
    kernel_args+=" ignition.firstboot ignition.platform.id=nvidiabluefield"
    kernel_args+=" ignore_loglevel"
    printf "%s" "${kernel_args}" > "${boot_args_v2}"

    printf "VenHw(F019E406-8C9C-11E5-8797-001ACA00BFC4)/Image" > "${boot_path}"
    printf "Linux from rshim" > "${boot_desc}"

    # Build mlx-mkbfb command
    local mkbfb_args=(
        --image "${kernel_path}"
        --initramfs "${initramfs_path}"
        --capsule "/root/RedHat.cap"
        --boot-args-v0 "${boot_args_v0}"
        --boot-args-v2 "${boot_args_v2}"
        --boot-path "${boot_path}"
        --boot-desc "${boot_desc}"
    )

    # Add --info if infojson was provided
    if [[ -n "${infojson_path}" ]]; then
        mkbfb_args+=(--info "${infojson_path}")
    fi

    log "Building BFB image..."
    "${SCRIPT_DIR}/bfscripts/mlx-mkbfb" \
        "${mkbfb_args[@]}" \
        "${WORKSPACE}/default.bfb" "${WORKSPACE}/${output_name}"

    mv "${WORKSPACE}/${output_name}" "${output_path}"

    log "BFB image ready: ${output_path}"
}

# ------------------------------------------------------------------------------
# Main
# ------------------------------------------------------------------------------

build_image_name() {
    local name="${IMG_BASE_NAME}"
    [[ -n "${RHCOS_VERSION:-}" ]] && name="${name}_${RHCOS_VERSION}"
    echo "${name}"
}

main() {
    # Default paths
    local coreos_kernel="${SCRIPT_DIR}/rhcos_${RHCOS_VERSION:-}-live-kernel.aarch64"
    local coreos_initramfs="${SCRIPT_DIR}/rhcos_${RHCOS_VERSION:-}-live-initramfs.aarch64.img"
    local coreos_rootfs="${SCRIPT_DIR}/rhcos_${RHCOS_VERSION:-}-live-rootfs.aarch64.img"
    local default_bfb="" capsule="" infojson=""
    local output_bfb=""

    # Parse arguments
    local opts
    opts=$(getopt -o h --longoptions 'help,kernel:,initramfs:,rootfs:,bfb-container:,default-bfb:,capsule:,infojson:,outfile:' -- "$@") \
        || die "Failed to parse options"

    eval set -- "${opts}"
    while true; do
        case "$1" in
            -h|--help)      usage ;;
            --kernel)       coreos_kernel="$2"; shift 2 ;;
            --initramfs)    coreos_initramfs="$2"; shift 2 ;;
            --rootfs)       coreos_rootfs="$2"; shift 2 ;;
            --default-bfb)  default_bfb="$2"; shift 2 ;;
            --capsule)      capsule="$2"; shift 2 ;;
            --infojson)     infojson="$2"; shift 2 ;;
            --outfile)      output_bfb="$2"; shift 2 ;;
            --)             shift; break ;;
            *)              die "Unexpected option: $1" ;;
        esac
    done

    # Build default output filename if not specified
    if [[ -z "${output_bfb}" ]]; then
        local img_name
        img_name="$(build_image_name)"
        # Add _meta_ suffix when infojson is provided
        if [[ -n "${infojson}" ]]; then
            img_name="${img_name}_meta"
        fi
        output_bfb="${SCRIPT_DIR}/output/${img_name}_${DATETIME}.bfb"
    fi

    # Setup workspace
    mkdir -p "${WORKSPACE}"

    # Handle bootimages (default.bfb and capsule)
    # These two must be provided together, or both come from the RPM
    if [[ -n "${default_bfb}" || -n "${capsule}" ]]; then
        # User provided at least one - require both
        [[ -n "${default_bfb}" ]] || die "--capsule requires --default-bfb"
        [[ -n "${capsule}" ]]     || die "--default-bfb requires --capsule"
        [[ -f "${default_bfb}" ]] || die "--default-bfb file not found: ${default_bfb}"
        [[ -f "${capsule}" ]]     || die "--capsule file not found: ${capsule}"
        cp "${default_bfb}" "${WORKSPACE}/default.bfb"
        cp "${capsule}" "${WORKSPACE}/boot_update2.cap"
    else
        # Use bootimages from RPM
        ensure_bootimages
        cp "${BOOTIMAGES_DIR}/lib/firmware/mellanox/boot/default.bfb" "${WORKSPACE}/default.bfb"
        cp "${BOOTIMAGES_DIR}/lib/firmware/mellanox/boot/capsule/boot_update2.cap" "${WORKSPACE}/boot_update2.cap"
    fi

    # Validate infojson if provided (it's optional and independent)
    if [[ -n "${infojson}" ]]; then
        [[ -f "${infojson}" ]] || die "--infojson file not found: ${infojson}"
    fi

    # Validate input files
    [[ -f "${coreos_kernel}" ]]   || die "Kernel not found: ${coreos_kernel}"
    [[ -f "${coreos_initramfs}" ]] || die "Initramfs not found: ${coreos_initramfs}"
    [[ -f "${coreos_rootfs}" ]]   || die "Rootfs not found: ${coreos_rootfs}"

    # Prepare kernel and combined initramfs
    log "Preparing kernel and initramfs..."
    cp --force "${coreos_kernel}" "${WORKSPACE}/kernel"
    cat "${coreos_initramfs}" "${coreos_rootfs}" > "${WORKSPACE}/initramfs_final"

    # Build the BFB
    build_bfb "${WORKSPACE}/initramfs_final" "${output_bfb}" "${infojson}"
}

main "$@"
