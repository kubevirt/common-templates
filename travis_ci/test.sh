#!/bin/bash
#
# This file is part of the KubeVirt project
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#
# Copyright 2019 Red Hat, Inc.
#
set -ex
if [ -z "$1" ]; then
	echo "First parameter should contain name of OS" && exit 1
fi

if [ -z "$2" ]; then
	echo "Second parameter should contain workload of OS" && exit 1
fi

name=$1
workload=$2

travis_fold_start(){
    echo -e "travis_fold:start:details\033[33;1mDetails\033[0m"
}

travis_fold_end(){
    echo -e "\ntravis_fold:end:details\r"
}

# Generate templates
make generate
# Limit required memory of large templates
bash automation/x-limit-ram-size.sh

# Download images
case "$name" in
"fedora")
	curl -fL -o "$name" https://download.fedoraproject.org/pub/fedora/linux/releases/30/Cloud/x86_64/images/Fedora-Cloud-Base-30-1.2.x86_64.qcow2
    ;;
"ubuntu")
	curl -fL -o "$name" http://cloud-images.ubuntu.com/bionic/current/bionic-server-cloudimg-amd64.img
    ;;
"opensuse")
	curl -fL -o "$name" https://download.opensuse.org/repositories/Cloud:/Images:/Leap_15.0/images/openSUSE-Leap-15.0-OpenStack.x86_64-0.0.4-Buildlp150.12.12.qcow2
    ;;
"centos7")
	curl -fL http://cloud.centos.org/centos/7/images/CentOS-7-x86_64-GenericCloud.qcow2.xz | xz -d > "$name"
    ;;
"centos6")
	curl -fL http://cloud.centos.org/centos/6/images/CentOS-6-x86_64-GenericCloud.qcow2.xz | xz -d > "$name"
    ;;
"centos8")
	curl -fL -o "$name" https://cloud.centos.org/centos/8/x86_64/images/CentOS-8-GenericCloud-8.1.1911-20200113.3.x86_64.qcow2
    ;;
esac

# Prepare image
mkdir -p "$PWD/pvs/$name"
qemu-img convert -p -O raw $name "$PWD/pvs/$name/disk.img"
sudo chown 107:107 "$PWD/pvs/$name/disk.img"
sudo chmod -R a+X "$PWD/pvs"

size_MB=$(( $(qemu-img info $name --output json | jq '.["virtual-size"]') / 1024 / 1024 + 128 ))
# Create PV and PVC
bash create-minikube-pvc.sh "$name" "${size_MB}M" "$PWD/pvs/$name/" | tee | oc apply -f -

#get all template sizes
templates=("dist/templates/$name-$workload-*.yaml")
sizes=()
for template in ${templates[@]}; do
    #-5 means strip .yaml postfix
    sizes+=($(echo $template | awk -F '-' '{print substr($NF, RSTART, (length($NF)-5))}'))
done

oc create -n kubevirt -f - <<EOF
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: kubevirt-config
  namespace: kubevirt
data:
  feature-gates: "DataVolumes"
---
EOF

echo "Deploying CDI"
export CDI_VERSION=$(curl -s https://github.com/kubevirt/containerized-data-importer/releases/latest | grep -o "v[0-9]\.[0-9]*\.[0-9]*")
oc create -f https://github.com/kubevirt/containerized-data-importer/releases/download/$CDI_VERSION/cdi-operator.yaml
oc create -f https://github.com/kubevirt/containerized-data-importer/releases/download/$CDI_VERSION/cdi-cr.yaml
oc rollout status -n cdi deployment/cdi-operator

oc create namespace openshift-cnv-base-images

# Deploy template validator (according to https://github.com/kubevirt/kubevirt-template-validator/blob/master/README.md)
echo "Deploying template validator"

VALIDATOR_VERSION=$(curl https://api.github.com/repos/kubevirt/kubevirt-template-validator/tags| jq -r '.[].name' | sort -r | head -1 )
rm -rf kubevirt-template-validator
git clone -b ${VALIDATOR_VERSION} --depth 1 https://github.com/kubevirt/kubevirt-template-validator kubevirt-template-validator

oc create -f kubevirt-template-validator/cluster/okd/manifests/template-view-role.yaml

sed "s|image:.*|image: quay.io/kubevirt/kubevirt-template-validator:${VALIDATOR_VERSION}|" < kubevirt-template-validator/cluster/okd/manifests/service.yaml | \
	sed "s|imagePullPolicy: Always|imagePullPolicy: IfNotPresent|g" | \
	oc create -f -

timeout=300
sample=5

# Wait for validator pods to be ready
oc rollout -n kubevirt status deployment/virt-template-validator

# Deploy templates
echo "Deploying templates"
oc create -n default -f dist/templates

# Used to store the exit code of the webhook creation command
webhookUpdated=1
webhookUpdateRetries=10

while [ $webhookUpdated != 0 ];
do
  if [ $webhookUpdateRetries == 0 ];
  then
    echo Retry count for template validator ca bundle injection reached
    exit 1
  fi

  webhookUpdateRetries=$((webhookUpdateRetries-1))

  VALIDATOR_POD=$(oc get pod -n kubevirt -l kubevirt.io=virt-template-validator -o json | jq -r .items[0].metadata.name)
  if [ "$VALIDATOR_POD" == "" ];
  then
    # Retry if an error occured
    continue
  fi

  CA_BUNDLE=$(oc exec -n kubevirt $VALIDATOR_POD -- /bin/cat /var/run/secrets/kubernetes.io/serviceaccount/service-ca.crt | base64 -w 0)
  if [ "$CA_BUNDLE" == "" ];
  then
    # Retry if an error occured
    continue
  fi

  sed "s/\${CA_BUNDLE}/${CA_BUNDLE}/g" < kubevirt-template-validator/cluster/okd/manifests/validating-webhook.yaml | oc apply -f -

  # If the webhook failed to be created, retry
  webhookUpdated=$?
done

VALIDATOR_PODS=($(oc get pods -n kubevirt -l kubevirt.io=virt-template-validator -ocustom-columns=name:metadata.name --no-headers))

for size in ${sizes[@]}; do
    vm_name="$(oc get -n default -f dist/templates/${name}-${workload}-${size}.yaml -ocustom-columns=name:metadata.name --no-headers)"
    oc process -n default -o json $vm_name NAME=$vm_name PVCNAME=$name | \
    jq '.items[0].metadata.labels["vm.kubevirt.io/template.namespace"]="default"' | \
	  oc apply -f -

	  for pod in ${VALIDATOR_PODS[@]}; do
	    oc logs -n kubevirt $pod
	  done

	  oc describe vm $vm_name
    # start vm
    virtctl start $vm_name

    set +e
    travis_fold_start
    current_time=0
    #check if vm is running
    while [[ $(oc get vmi $vm_name -o json | jq -r '.status.phase') != Running ]] ; do
      oc describe vmi $vm_name
      current_time=$((current_time + sample))
      if [ $current_time -gt $timeout ]; then
        exit 1 
      fi
      sleep $sample;
    done
    travis_fold_end
    set -e

    # check if vm is alive
    virtctl console --timeout=5 $vm_name | tee /dev/stderr | egrep -m 1 "Welcome|systemd"

    #delete vm
    oc process -n default -o json $vm_name NAME=$vm_name PVCNAME=$name |
	  oc delete -f -

    #wait until vm is deleted
    while oc get vmi $vm_name 2> >(grep "not found") ; do sleep 15; done
done
