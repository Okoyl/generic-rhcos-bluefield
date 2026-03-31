# Generic RHCOS BFB Image Generation

This simple project generates a Red Hat CoreOS image for NVIDIA BlueField devices.

### Prepare
Set envrioment variables
```sh
export RHCOS_VERSION=4.22.0-ec.4
# OpenShift Pull Secret
export PULL_SECRET="~/pull-secret.json"
```

Set Image target
```sh
version=$(oc adm release info -o json "quay.io/openshift-release-dev/ocp-release:$RHCOS_VERSION-aarch64" | jq -r '.displayVersions["machine-os"].Version')
export TARGET_IMAGE="quay.io/openshift-release-dev/ocp-v4.0-art-dev:${version}-coreos"
```

### Build Red Hat CoreOS Artifacts
```sh
podman build -f rhcos-generic.Containerfile \
          --authfile $PULL_SECRET \
          --build-arg TARGET_IMAGE=$TARGET_IMAGE \
          --tag "rhcos-generic:$RHCOS_VERSION-latest"
```

### Create BFB Image

```sh
skopeo copy containers-storage:localhost/rhcos-generic:$RHCOS_VERSION-latest oci-archive:rhcos-generic_$RHCOS_VERSION.ociarchive
sudo custom-coreos-disk-images/custom-coreos-disk-images.sh \
        --ociarchive rhcos-generic_$RHCOS_VERSION.ociarchive \
        --platforms live \
        --metal-image-size 5000

./make_bfb.sh
```


