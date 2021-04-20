#!/bin/bash

set -e

# Build a K8s cluster from kubevirtci
cd "${PWD}/../kubevirtci"
#apt-get update && apt-get install -y --no-install-recommends --no-upgrade expect ansible intltool libosinfo-1.0 libssl-dev osinfo-db-tools python-gi && rm -rf /var/lib/apt/lists/*
export KUBEVIRTCI_TAG=$(curl -L https://storage.googleapis.com/kubevirt-prow/release/kubevirt/kubevirtci/latest)
export KUBEVIRTCI_GOCLI_CONTAINER=quay.io/kubevirtci/gocli:"${KUBEVIRTCI_TAG}"
export KUBEVIRT_PROVIDER=k8s-1.20
export KUBEVIRT_MEMORY_SIZE=10240M
export KUBEVIRT_PROVIDER_EXTRA_ARGS="--registry-port 5000"
make cluster-up
export KUBECONFIG=$(cluster-up/kubeconfig.sh)

# Login details for the Quay Registry
cat "$QUAY_PASSWORD" | docker login --username $(cat "$QUAY_USER") --password-stdin=true quay.io

# Execute the script to build a CentOS/Fedora Container Disk Image
cd "${PWD}/../common-templates/dvtemplates/"
#Run the script from common-templates
./new_cdi_image.sh
exit_status=$?
echo $exit_status
exit $exit_status
