#!/bin/bash

cd ${PWD}/../kubevirtci
#apt-get update && apt-get install -y --no-install-recommends --no-upgrade expect ansible intltool libosinfo-1.0 libssl-dev osinfo-db-tools python-gi && rm -rf /var/lib/apt/lists/*
export KUBEVIRTCI_TAG=$(curl -L https://storage.googleapis.com/kubevirt-prow/release/kubevirt/kubevirtci/latest)
export KUBEVIRTCI_GOCLI_CONTAINER=quay.io/kubevirtci/gocli:${KUBEVIRTCI_TAG}
export KUBEVIRT_PROVIDER=k8s-1.20
#export KUBEVIRT_NUM_NODES=$1
export KUBEVIRT_MEMORY_SIZE=10240M
export KUBEVIRT_PROVIDER_EXTRA_ARGS="--registry-port 5000"
make cluster-up
export KUBECONFIG=$(cluster-up/kubeconfig.sh)
cd ${PWD}/../common-templates/dvtemplates/
#cat $QUAY_PASSWORD | docker login --username $(cat $QUAY_USER) --password-stdin=true quay.io
#Run the script from common-templates
export OS_IMAGE=$1
./new_cdi_image.sh
exit $?
