ARG TARGET_IMAGE

FROM ${TARGET_IMAGE} AS base

COPY ignition/bin/arm64/ignition /usr/lib/dracut/modules.d/30ignition/ignition
COPY ignition/dracut/30ignition/module-setup.sh /usr/lib/dracut/modules.d/30ignition/module-setup.sh

RUN \
  mkdir /var/tmp; \
  set -xe; kver=$(ls /usr/lib/modules); env DRACUT_NO_XATTR=1 dracut -vf /usr/lib/modules/$kver/initramfs.img "$kver"; \
  rm -rf /var/cache/* /var/log/* /etc/machine-id && \
  update-pciids && \
  ostree container commit

