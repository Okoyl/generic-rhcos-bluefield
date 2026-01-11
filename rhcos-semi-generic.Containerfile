ARG BUILDER_IMAGE
ARG TARGET_IMAGE
ARG RHCOS_VERSION
ARG D_CONTAINER_VER=0
ARG D_DOCA_VERSION
ARG D_OFED_VERSION
ARG OFED_SRC_LOCAL_DIR=${D_OFED_SRC_DOWNLOAD_PATH}/MLNX_OFED_SRC-${D_OFED_VERSION}

FROM ${BUILDER_IMAGE} AS builder

ARG D_DOCA_VERSION
ARG D_OFED_VERSION
ARG D_CONTAINER_VER
ARG OFED_SRC_LOCAL_DIR


ARG DOCA_SOURCES_URL="https://linux.mellanox.com/public/repo/doca/${D_DOCA_VERSION}/SOURCES"

WORKDIR /root

RUN KVER=$(ls /usr/lib/modules | head -n1) && \
  echo "KVER=$KVER" >> /kernelver.env  

ARG D_OFED_SRC_ARCHIVE="MLNX_OFED_SRC-${D_OFED_SRC_TYPE}${D_OFED_VERSION}.tgz"

RUN dnf install -y automake autoconf libtool perl

RUN wget --no-check-certificate -O ${D_OFED_SRC_ARCHIVE} ${DOCA_SOURCES_URL}/mlnx_ofed/${D_OFED_SRC_ARCHIVE}; \
  if [ $? -ne 0 ]; then \
  wget --no-check-certificate -O ${D_OFED_SRC_ARCHIVE} ${DOCA_SOURCES_URL}/MLNX_OFED/${D_OFED_SRC_ARCHIVE}; \
  fi

RUN if file ${D_OFED_SRC_ARCHIVE} | grep compressed; then \
  tar -xzf ${D_OFED_SRC_ARCHIVE}; \
  else \
  mv ${D_OFED_SRC_ARCHIVE}/MLNX_OFED_SRC-${D_OFED_VERSION} . ; \
  fi

RUN set -x && \
  source /kernelver.env && \
  perl /root/MLNX_OFED_SRC-${D_OFED_VERSION}/install.pl --without-depcheck --distro rhel --kernel ${KVER} --kernel-sources /lib/modules/${KVER}/build \
  --kernel-only --build-only \
  --with-iser --with-srp --with-isert --with-knem --with-xpmem --fwctl \
  --with-mlnx-tools --with-ofed-scripts --copy-ifnames-udev

RUN mkdir -p /build/rpmbuild/{BUILD,RPMS,SOURCES,SPECS,SRPMS}

ENV HOME=/build

WORKDIR /root

RUN SRPMS=("tmfifo" "pwr-mlxbf" "mlxbf-ptm" "gpio-mlxbf3" "mlxbf-bootctl" \
  "mlxbf-pmc" "mlxbf-livefish" "mlxbf-gige" "mlx-trio" "ipmb-dev-int" "ipmb-host" "pinctrl-mlxbf3" "sdhci-of-dwcmshc") && \
  wget -r -np -nd -A rpm -e robots=off "${DOCA_SOURCES_URL}/SoC/" --accept-regex="$(IFS='|'; echo "(${SRPMS[*]/%/.+\.rpm})")"

RUN source /kernelver.env && \
  for package in *.src.rpm; do \
  rpmbuild --rebuild $package --define 'KMP 1' --define "KVERSION $KVER" --define "_sourcedir $(pwd)" --define "debug_package %{nil}" || exit 1; \
  rm -f $package; \
  done

RUN SRPMS_PATCH_REQUIRED=("mlxbf-pka") && \
  wget -r -np -nd -A rpm -e robots=off "${DOCA_SOURCES_URL}/SoC" --accept-regex="$(IFS='|'; echo "(${SRPMS_PATCH_REQUIRED[*]/%/.+\.rpm})")"

RUN source /kernelver.env && \
  PACKAGE="mlxbf-pka" && \
  rpm2cpio $PACKAGE-*.src.rpm | cpio -idm && \
  rm -f $PACKAGE-*.src.rpm && \
  tar -xvf $PACKAGE-*.tar.gz -o && rm -f $PACKAGE-*.tar.gz && \
  SRCDIR=$(basename "$PACKAGE"*) && \
  tar -czf "${SRCDIR}.tar.gz" $SRCDIR && \
  rpmbuild -ba $SRCDIR/*.spec --define 'KMP 1' --define 'compat_cflags -DRHEL_DRM_VERSION=6 -DRHEL_DRM_PATCHLEVEL=12' --define "KVERSION $KVER" --define "_sourcedir $(pwd)" --define "debug_package %{nil}"

RUN ls /root/MLNX_OFED_SRC-${D_OFED_VERSION}/RPMS/redhat-release-*/aarch64

RUN cd /root/MLNX_OFED_SRC-${D_OFED_VERSION}/RPMS/redhat-release-*/aarch64 && \
  rm -f *-devel*.rpm *-debugsource*.rpm *-debuginfo*.rpm *-source*.rpm && \
  rm -f xpmem-*.rpm knem-*.rpm && \
  mkdir /root/rpms && \
  mv *.rpm /root/rpms && \
  mv /build/rpmbuild/RPMS/aarch64/*.rpm /root/rpms && \
  cd /root/rpms && \
  dnf download mstflint && \
  dnf clean all
######################################################################

FROM ${TARGET_IMAGE} AS base

ARG RHCOS_VERSION
ARG D_DOCA_VERSION
ARG OFED_SRC_LOCAL_DIR

RUN mkdir /tmp/rpms

COPY --from=builder /root/rpms/*.rpm /tmp/rpms

WORKDIR /

RUN rm opt && mkdir -p usr/opt && ln -s usr/opt opt; \
  ls /tmp/rpms && \
  # Install kernel modules
  rm -f /tmp/rpms/mlnx-ofa_kernel-devel*.rpm \
  /tmp/rpms/kmod-mlnx-ofa_kernel-debuginfo*.rpm \
  /tmp/rpms/mlnx-ofa_kernel-debugsource*.rpm \
  /tmp/rpms/mlnx-ofa_kernel-source*.rpm \
  /tmp/rpms/*-devel*.rpm \
  /tmp/rpms/*-debugsource*.rpm \
  /tmp/rpms/*-debuginfo*.rpm && \
  rpm -ivh --nodeps /tmp/rpms/*.rpm

RUN cp /usr/share/doc/mlnx-ofa_kernel/vf-net-link-name.sh /etc/infiniband/vf-net-link-name.sh && \
  cp /usr/share/doc/mlnx-ofa_kernel/82-net-setup-link.rules /usr/lib/udev/rules.d/82-net-setup-link.rules && \
  echo "L+ /opt/mellanox - - - - /usr/opt/mellanox" > /etc/tmpfiles.d/link-opt.conf

RUN \
  rm /opt && ln -s /var/opt /opt; \
  set -xe; kver=$(ls /usr/lib/modules); env DRACUT_NO_XATTR=1 dracut -vf /usr/lib/modules/$kver/initramfs.img "$kver"; \
  rm -rf /var/cache/* /var/log/* /etc/machine-id && \
  update-pciids && \
  ostree container commit; \
  echo 'root:password' | chpasswd

LABEL "rhcos.version"="${RHCOS_VERSION}"
LABEL "rhcos.doca.version"="${D_DOCA_VERSION}"
LABEL "com.coreos.osname"=rhcos
LABEL "rhcos.custom.tag"="${IMAGE_TAG}"
