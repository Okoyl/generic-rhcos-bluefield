#!/bin/bash
set -e

export PROJDIR="$(realpath "$(dirname "$0")")"
WDIR=workspace
mkdir -p $WDIR
export WDIR=$(readlink -f $WDIR)


IMG_NAME="rhcos"

kernel="$WDIR/kernel"
initramfs="$WDIR/initramfs"
initramfs_final="$WDIR/initramfs_final"

DATETIME=$(date +'%F_%H-%M-%S')

if [ -n "$RHCOS_VERSION" ]; then
    IMG_NAME="${IMG_NAME}_${RHCOS_VERSION}"
fi

if [ -n "$DOCA_VERSION" ]; then
    IMG_NAME="${IMG_NAME}_${DOCA_VERSION}"
fi

if [ ! -d $WDIR/bootimages ] || [ -z "$(ls -A $WDIR/bootimages 2>/dev/null)" ]; then
  mkdir -p $WDIR/bootimages
  pushd $WDIR/bootimages

  curl -O https://linux.mellanox.com/public/repo/doca/3.1.0/rhel9.6/arm64-dpu/mlxbf-bootimages-signed-4.12.0-13720.aarch64.rpm
  rpm2cpio mlxbf-bootimages-signed*.rpm | cpio -idm

  popd
fi


buildbfb() {
    ARG_INITRAMFS=$1
    ARG_OUTFILE=$2

    BFB_OUTDIR=$(dirname "${ARG_OUTFILE}")
    BFB_OUTFILENAME=$(basename "${ARG_OUTFILE}")

    mkdir -p "${BFB_OUTDIR}"

    KERNEL_DBG_ARGS="ignore_loglevel"

    boot_args=$(mktemp)
    boot_args2=$(mktemp)
    boot_path=$(mktemp)
    boot_desc=$(mktemp)

    printf "console=ttyAMA0 earlycon=pl011,0x01000000 earlycon=pl011,0x01800000 initrd=initramfs" > "$boot_args"
    printf "console=hvc0 console=ttyAMA0 earlycon=pl011,0x13010000 initrd=initramfs $KERNEL_DBG_ARGS" > "$boot_args2"


    printf "VenHw(F019E406-8C9C-11E5-8797-001ACA00BFC4)/Image" > "$boot_path"
    printf "Linux from rshim" > "$boot_desc"

    $PROJDIR/bfscripts/mlx-mkbfb \
        --image "$kernel" \
        --initramfs "$ARG_INITRAMFS" \
        --capsule "$WDIR/boot_update2.cap" \
        --boot-args-v0 "$boot_args" \
        --boot-args-v2 "$boot_args2" \
        --boot-path "$boot_path" \
        --boot-desc "$boot_desc" \
        $WDIR/default.bfb $WDIR/${BFB_OUTFILENAME}

    mv "${WDIR}/${BFB_OUTFILENAME}" "${ARG_OUTFILE}"

    echo "BFB Image is Ready! ${ARG_OUTFILE}"
    rm $boot_args
    rm $boot_args2
    rm $boot_path
    rm $boot_desc
}


main() {
    # default values to keep existing behavior
    coreos_kernel="${PROJDIR}/rhcos-${RHCOS_VERSION}-aarch64-live-kernel.aarch64"
    coreos_initramfs="${PROJDIR}/rhcos-${RHCOS_VERSION}-aarch64-live-initramfs.aarch64.img"
    coreos_rootfs="${PROJDIR}/rhcos-${RHCOS_VERSION}-aarch64-live-rootfs.aarch64.img"
    coreos_bfb_container="rhcos:${RHCOS_VERSION}-latest"
    output_bfb_filepath="${PROJDIR}/output/${IMG_NAME}_${DATETIME}.bfb"

    # Call getopt to validate the provided input.
    options=$(getopt --options - --longoptions 'kernel:,initramfs:,rootfs:,bfb-container:,default-bfb:,capsule:,infojson:,outfile:' -- "$@")
    if [ $? -ne 0 ]; then
        echo "Incorrect options provided"
        exit 1
    fi
    eval set -- "$options"
    while true; do
        case "$1" in
        --kernel)
            shift # The arg is next in position args
            coreos_kernel=$1
            ;;
        --initramfs)
            shift # The arg is next in position args
            coreos_initramfs=$1
            ;;
        --rootfs)
            shift # The arg is next in position args
            coreos_rootfs=$1
            ;;
        --bfb-container)
            shift # The arg is next in position args
            coreos_bfb_container=$1
            ;;
        --default-bfb)
            shift # The arg is next in position args
            default_bfb=$1
            ;;
        --capsule)
            shift # The arg is next in position args
            capsule=$1
            ;;
        --infojson)
            shift # The arg is next in position args
            infojson=$1
            ;;
        --outfile)
            shift # The arg is next in position args
            output_bfb_filepath=$1
            ;;
        --)
            shift
            break
            ;;
        esac
        shift
    done
    # If the default bfb, capsule and infojson weren't provided on
    # the command line then we'll pull them from the container
    if [ -z "${default_bfb}${capsule}${infojson}" ]; then
        cp $WDIR/bootimages/lib/firmware/mellanox/boot/default.bfb $WDIR/default.bfb
        cp $WDIR/bootimages/lib/firmware/mellanox/boot/capsule/boot_update2.cap $WDIR/boot_update2.cap
    else
        # Otherwise we'll use the ones provided by the user.
        if [ ! -f "${default_bfb}" ] || [ ! -f "${capsule}" ] || [ ! -f "${infojson}" ]; then
            echo "Must provide all of --default-bfb, --capsule, and --infojson if providing any." >&2
            exit 1
        fi
        cp "${default_bfb}" $WDIR/default.bfb
        cp "${capsule}" $WDIR/boot_update2.cap
    fi

    cp --force "${coreos_kernel}" $kernel
    cat "${coreos_initramfs}" "${coreos_rootfs}" > $initramfs_final

    buildbfb "${initramfs_final}" "${output_bfb_filepath}"
}

main "$@"
