ARG TARGET_IMAGE

FROM ${TARGET_IMAGE} AS base

# Copy custom ignition binary to ALL locations where dracut modules might pick it up:
# 1. /usr/bin/ignition - system path
# 2. 30ignition module directory
# 3. 35coreos-ignition module directory (RHCOS specific - this module runs AFTER 30ignition and may overwrite)
COPY ignition/bin/arm64/ignition /usr/bin/ignition
COPY ignition/bin/arm64/ignition /usr/lib/dracut/modules.d/30ignition/ignition
COPY ignition/bin/arm64/ignition /usr/lib/dracut/modules.d/35coreos-ignition/ignition
COPY ignition/dracut/30ignition/module-setup.sh /usr/lib/dracut/modules.d/30ignition/module-setup.sh

RUN \
  set -xe; \
  echo "=== Checking 35coreos-ignition module contents ===" && \
  ls -la /usr/lib/dracut/modules.d/35coreos-ignition/ && \
  cat /usr/lib/dracut/modules.d/35coreos-ignition/module-setup.sh | grep -A5 "install()" || true && \
  echo "=== Verifying custom ignition before dracut ===" && \
  /usr/bin/ignition --help 2>&1 | head -20 && \
  /usr/bin/ignition --help 2>&1 | grep -q nvidiabluefield && echo "✓ nvidiabluefield found in /usr/bin/ignition" || (echo "✗ nvidiabluefield NOT in /usr/bin/ignition!" && exit 1) && \
  /usr/lib/dracut/modules.d/35coreos-ignition/ignition --help 2>&1 | grep -q nvidiabluefield && echo "✓ nvidiabluefield found in 35coreos-ignition/ignition" || echo "⚠ nvidiabluefield NOT in 35coreos-ignition/ignition" && \
  mkdir -p /var/tmp && \
  kver=$(ls /usr/lib/modules) && \
  env DRACUT_NO_XATTR=1 dracut -vf /usr/lib/modules/$kver/initramfs.img "$kver" && \
  rm -rf /var/cache/* /var/log/* /etc/machine-id && \
  update-pciids && \
  ostree container commit

