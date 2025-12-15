# Generic RHCOS BFB Image Generation

This simple project generates a Red Hat CoreOS image for NVIDIA BlueField devices.

### Prepare


Download Red Hat CoreOS Artifacts, in this example we are using 4.20.0
```sh
curl -O https://mirror.openshift.com/pub/openshift-v4/aarch64/dependencies/rhcos/4.20/latest/rhcos-4.20.0-aarch64-live-kernel.aarch64
curl -O https://mirror.openshift.com/pub/openshift-v4/aarch64/dependencies/rhcos/4.20/latest/rhcos-4.20.0-aarch64-live-initramfs.aarch64.img
curl -O https://mirror.openshift.com/pub/openshift-v4/aarch64/dependencies/rhcos/4.20/latest/rhcos-4.20.0-aarch64-live-rootfs.aarch64.img
```

### Build

```sh
export RHCOS_VERSION=4.20.0
./make_bfb.sh
```


