# Generic RHCOS BFB Image Generation

This simple project generates a Red Hat CoreOS image for NVIDIA BlueField devices.

### Prepare
Set envrioment variables
```sh
export RHCOS_VERSION=4.20.9
# DOCA Stack
export DOCA_VERSION=3.1.0
export OFED_VERSION=25.07-0.9.7.0
# OpenShift Pull Secret
export PULL_SECRET="~/pull-secret.json"
```

Set Images
```sh
# Driver Toolkit Image
export BUILDER_IMAGE=$(oc adm release info --image-for driver-toolkit "quay.io/openshift-release-dev/ocp-release:"$RHCOS_VERSION"-aarch64")
# Target Node Image
version=$(oc adm release info -o json "quay.io/openshift-release-dev/ocp-release:$RHCOS_VERSION-aarch64" | jq -r '.displayVersions["machine-os"].Version')
export TARGET_IMAGE="quay.io/openshift-release-dev/ocp-v4.0-art-dev:${version}-coreos"
```

### Build Red Hat CoreOS Artifacts
```sh
podman build -f rhcos-semi-generic.Containerfile \
          --authfile $PULL_SECRET \
          --build-arg RHCOS_VERSION=$RHCOS_VERSION \
          --build-arg D_DOCA_VERSION=$DOCA_VERSION \
          --build-arg D_OFED_VERSION=$OFED_VERSION \
          --build-arg BUILDER_IMAGE=$BUILDER_IMAGE \
          --build-arg TARGET_IMAGE=$TARGET_IMAGE \
          --tag "rhcos-semigeneric:$RHCOS_VERSION-latest"
```

### Create BFB Image

```sh
skopeo copy containers-storage:localhost/rhcos-semigeneric:$RHCOS_VERSION-latest oci-archive:rhcos-semigeneric_$RHCOS_VERSION.ociarchive
sudo custom-coreos-disk-images/custom-coreos-disk-images.sh \
        --ociarchive rhcos-semigeneric_$RHCOS_VERSION.ociarchive \
        --platforms live \
        --metal-image-size 5000

./make_bfb.sh
```


