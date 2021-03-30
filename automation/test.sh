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

namespace="kubevirt"

_curl() {
	# this dupes the baseline "curl" command line, but is simpler
	# wrt shell quoting/expansion.
	if [ -n "${GITHUB_TOKEN}" ]; then
		curl -H "Authorization: token ${GITHUB_TOKEN}" $@
	else
		curl $@
	fi
}
export KUBEVIRT_VERSION=$(_curl -L https://api.github.com/repos/kubevirt/kubevirt/releases | \
            jq '.[] | select(.prerelease==false) | .name' | sort -V | tail -n1 | tr -d '"')

ocenv="OC"

if [ -z "$CLUSTERENV" ]
then
    export CLUSTERENV=$ocenv
fi

git submodule update --init

make generate

#set terminationGracePeriodSeconds to 0
for filename in dist/templates/*; do
    sed -i -e 's/^\(\s*terminationGracePeriodSeconds\s*:\s*\).*/\10/' $filename
done

curl -Lo virtctl \
    https://github.com/kubevirt/kubevirt/releases/download/$KUBEVIRT_VERSION/virtctl-$KUBEVIRT_VERSION-linux-amd64
chmod +x virtctl

oc apply -f https://github.com/kubevirt/kubevirt/releases/download/${KUBEVIRT_VERSION}/kubevirt-operator.yaml
oc apply -f https://github.com/kubevirt/kubevirt/releases/download/${KUBEVIRT_VERSION}/kubevirt-cr.yaml

sample=10
current_time=0
timeout=300

# Waiting for kubevirt cr to report available
oc wait --for=condition=Available --timeout=${timeout}s kubevirt/kubevirt -n $namespace

oc apply -f - <<EOF
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

key="/tmp/secrets/accessKeyId"
token="/tmp/secrets/secretKey"

if [ "${CLUSTERENV}" == "$ocenv" ]
then
    if test -f "$key" && test -f "$token"; then
      id=$(cat $key | tr -d '\n' | base64)
      token=$(cat $token | tr -d '\n' | base64 | tr -d ' \n')

      oc apply -n $namespace -f - <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: common-templates-container-disk-puller
  labels:
    app: containerized-data-importer
type: Opaque
data:
  accessKeyId: "${id}"
  secretKey: "${token}"
EOF
    fi
fi
echo "Deploying CDI"
#export CDI_VERSION=$(curl -s https://api.github.com/repos/kubevirt/containerized-data-importer/releases | \
#            jq '.[] | select(.prerelease==false) | .tag_name' | sort -V | tail -n1 | tr -d '"')

export CDI_VERSION="v1.29.0"
oc apply -f https://github.com/kubevirt/containerized-data-importer/releases/download/$CDI_VERSION/cdi-operator.yaml
oc apply -f https://github.com/kubevirt/containerized-data-importer/releases/download/$CDI_VERSION/cdi-cr.yaml

oc wait --for=condition=Available --timeout=${timeout}s CDI/cdi -n cdi

oc apply -f - <<EOF
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: cdi-role
  namespace: cdi
rules:
- apiGroups: ["cdi.kubevirt.io"]
  resources: ["datavolumes/source"]
  verbs: ["*"]
---
EOF

if [ "${CLUSTERENV}" == "$ocenv" ]
then
    export VALIDATOR_VERSION=$(curl -s https://api.github.com/repos/kubevirt/kubevirt-template-validator/releases | \
            jq '.[] | select(.prerelease==false) | .tag_name' | sort -V | tail -n1 | tr -d '"')

    git clone -b ${VALIDATOR_VERSION} --depth 1 https://github.com/kubevirt/kubevirt-template-validator kubevirt-template-validator
    VALIDATOR_DIR="kubevirt-template-validator/cluster/ocp4"
    sed -i 's/RELEASE_TAG/'$VALIDATOR_VERSION'/' ${VALIDATOR_DIR}/service.yaml
    oc apply -n kubevirt -f ${VALIDATOR_DIR}
    oc wait --for=condition=Available --timeout=${timeout}s deployment/virt-template-validator -n $namespace
    # Apply templates
    echo "Deploying templates"
    oc apply -n $namespace  -f dist/templates
fi

# add cpumanager=true label to all worker nodes
# to allow execution of tests using high performance profiles
oc label nodes -l node-role.kubernetes.io/worker cpumanager=true --overwrite

if [[ $TARGET =~ windows.* ]]; then
  ./automation/test-windows.sh $TARGET
else
  ./automation/test-linux.sh $TARGET
fi
