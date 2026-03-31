ARG TARGET_IMAGE

FROM ${TARGET_IMAGE} AS base

RUN cat <<EOF > /etc/yum.repos.d/kernelfix_mlxbf-pmc.repo
[10.2_kernel_fix_mlxbf-pmc]
name=10.2 kernel fix for mlxbf-pmc
baseurl=http://bfb.okoyl.xyz/misc/10.2_kernel_fix_mlxbf-pmc/rpm_repo/
gpgcheck=0
enabled=1
EOF

RUN dnf remove -y kernel kernel-core kernel-modules kernel-modules-core kernel-modules-extra && \
  dnf install --disablerepo="*" --enablerepo="10.2_kernel_fix_mlxbf-pmc" -y \
  kernel \
  kernel-core \
  kernel-modules \
  kernel-modules-core \
  kernel-modules-extra \
  && \
  dnf clean all

RUN \
  mkdir /var/tmp; \
  set -xe; kver=$(ls /usr/lib/modules); env DRACUT_NO_XATTR=1 dracut -vf /usr/lib/modules/$kver/initramfs.img "$kver"; \
  rm -rf /var/cache/* /var/log/* /etc/machine-id && \
  update-pciids && \
  ostree container commit

