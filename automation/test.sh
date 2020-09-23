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
# Copyright 2018 Red Hat, Inc.
#

set -ex

readonly TEMPLATES_SERVER="https://templates.ovirt.org/kubevirt"

_curl() {
	# this dupes the baseline "curl" command line, but is simpler
	# wrt shell quoting/expansion.
	if [ -n "${GITHUB_TOKEN}" ]; then
		curl -H "Authorization: token ${GITHUB_TOKEN}" $@
	else
		curl $@
	fi
}

#export KUBEVIRT_VERSION=$(_curl https://api.github.com/repos/kubevirt/kubevirt/tags| jq -r '.[].name' | sort -r | head -1 )
export KUBEVIRT_VERSION="v0.33.0"

git submodule update --init

make generate

#set terminationGracePeriodSeconds to 0
for filename in dist/templates/*; do
    sed -i -e 's/^\(\s*terminationGracePeriodSeconds\s*:\s*\).*/\10/' $filename
done

curl -Lo virtctl \
    https://github.com/kubevirt/kubevirt/releases/download/$KUBEVIRT_VERSION/virtctl-$KUBEVIRT_VERSION-linux-x86_64
chmod +x virtctl


export NAMESPACE="${NAMESPACE:-kubevirt}"

# Make sure that the VM is properly shut down on exit
trap '{ rm -rf ../kubevirt-template-validator; }' EXIT SIGINT SIGTERM SIGSTOP

oc apply -f https://github.com/kubevirt/kubevirt/releases/download/${KUBEVIRT_VERSION}/kubevirt-operator.yaml
oc apply -f https://github.com/kubevirt/kubevirt/releases/download/${KUBEVIRT_VERSION}/kubevirt-cr.yaml

oc apply -f - <<EOF
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: kubevirt-config
  namespace: kubevirt
  labels:
    kubevirt.io: ""
data:
  feature-gates: "DataVolumes, CPUManager, LiveMigration, ExperimentalIgnitionSupport, Sidecar, Snapshot"
  permitSlirpInterface: "true"
---
EOF

# Deploy template validator (according to https://github.com/kubevirt/kubevirt-template-validator/blob/master/README.md)
#echo "Deploying template validator"

#VALIDATOR_VERSION=$(_curl https://api.github.com/repos/kubevirt/kubevirt-template-validator/tags| jq -r '.[].name' | sort -r | head -1 )
#rm -rf ../kubevirt-template-validator
#git clone -b ${VALIDATOR_VERSION} --depth 1 https://github.com/kubevirt/kubevirt-template-validator ../kubevirt-template-validator

#oc apply -f ../kubevirt-template-validator/cluster/okd/manifests/template-view-role.yaml

#sed "s|image:.*|image: quay.io/kubevirt/kubevirt-template-validator:${VALIDATOR_VERSION}|" < ../kubevirt-template-validator/cluster/okd/manifests/service.yaml | \
#	sed "s|imagePullPolicy: Always|imagePullPolicy: IfNotPresent|g" | \
#	sed 's|apps\/v1beta1|apps\/v1|g' | \
#	oc apply -f -

# Wait for the validator deployment to be ready
#oc rollout status deployment/virt-template-validator -n $NAMESPACE


namespaces=(kubevirt)
if [[ $NAMESPACE != "kubevirt" ]]; then
  namespaces+=($NAMESPACE)
fi

timeout=300
sample=30

# Waiting for kubevirt cr to report available
oc wait --for=condition=Available --timeout=${timeout}s kubevirt/kubevirt -n $NAMESPACE

echo "Deploying CDI"
export CDI_VERSION=$(curl -s https://github.com/kubevirt/containerized-data-importer/releases/latest | grep -o "v[0-9]\.[0-9]*\.[0-9]*")
oc create -f https://github.com/kubevirt/containerized-data-importer/releases/download/$CDI_VERSION/cdi-operator.yaml
oc create -f https://github.com/kubevirt/containerized-data-importer/releases/download/$CDI_VERSION/cdi-cr.yaml
oc rollout status -n cdi deployment/cdi-operator

oc project kubevirt

# Apply templates
echo "Deploying templates"
oc apply -n kubevirt -f dist/templates

# Used to store the exit code of the webhook creation command
#webhookUpdated=1
#webhookUpdateRetries=10

#while [ $webhookUpdated != 0 ];
#do
  # Approve all CSRs to avoid an issue similar to this: https://github.com/kubernetes/frakti/issues/200
  # This is attempted before any call to 'oc exec' because there's suspect that more csr's have to be approved
  # over time and not only once after the cluster has been initiated.
  #oc adm certificate approve $(oc get csr -ocustom-columns=NAME:metadata.name --no-headers)

  #if [ $webhookUpdateRetries == 0 ];
  #then
    #echo Retry count for template validator ca bundle injection reached
    #exit 1
  #fi

  #webhookUpdateRetries=$((webhookUpdateRetries-1))

  #VALIDATOR_POD=$(oc get pod -n $NAMESPACE -l kubevirt.io=virt-template-validator -o json | jq -r .items[0].metadata.name)
  #if [ "$VALIDATOR_POD" == "" ];
  #then
    # Retry if an error occured
    #continue
  #fi

  #CA_BUNDLE=$(oc exec -n $NAMESPACE $VALIDATOR_POD -- /bin/cat /var/run/secrets/kubernetes.io/serviceaccount/service-ca.crt | base64 -w 0)
  #if [ "$CA_BUNDLE" == "" ];
  #then
    # Retry if an error occured
  #  continue
  #fi

  #sed "s/\${CA_BUNDLE}/${CA_BUNDLE}/g" < ../kubevirt-template-validator/cluster/okd/manifests/validating-webhook.yaml | oc apply -f -

  # If the webhook failed to be created, retry
  #webhookUpdated=$?
#done

#oc describe validatingwebhookconfiguration virt-template-validator

if [[ $TARGET =~ fedora.* ]]; then
  ./automation/test-rhel.sh $TARGET
fi

if [[ $TARGET =~ windows.* ]]; then
  ./automation/test-windows.sh $TARGET
fi
