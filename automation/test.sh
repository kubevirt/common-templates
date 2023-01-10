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

# This function will be used in release branches
function latest_patch_version() {
  local repo="$1"
  local minor_version="$2"

  # The loop is necessary, because GitHub API call cannot return more than 100 items
  local latest_version=""
  local page=1
  while true ; do
    # Declared separately to not mask return value
    local versions_in_page
    versions_in_page=$(
      curl --fail -s "https://api.github.com/repos/kubevirt/${repo}/releases?per_page=100&page=${page}" |
      jq '.[] | select(.prerelease==false) | .tag_name' |
      tr -d '"'
    )
    if [ $? -ne 0 ]; then
      return 1
    fi

    if [ -z "${versions_in_page}" ]; then
      break
    fi

    latest_version=$(
      echo "${versions_in_page} ${latest_version}" |
      tr " " "\n" |
      grep "^${minor_version}\\." |
      sort --version-sort |
      tail -n1
    )

    ((++page))
  done

  echo "${latest_version}"
}

function latest_version() {
  local repo="$1"

  # The API call sorts releases by creation timestamp, so it is enough to request only a few latest ones.
  curl --fail -s "https://api.github.com/repos/kubevirt/${repo}/releases" | \
    jq '.[] | select(.prerelease==false) | .tag_name' | \
    tr -d '"' | \
    sort --version-sort | \
    tail -n1
}

# Latest released Kubevirt version
export KUBEVIRT_VERSION=$(latest_version "kubevirt")

# Latest released CDI version
export CDI_VERSION=$(latest_version "containerized-data-importer")

# switch to faster storage class for widows tests (slower storage class is causing timeouts due 
# to not able to copy whole windows disk into cluster)
if [[ "$(oc get storageclass | grep -q 'ssd-csi (default)')" && $TARGET =~ windows.* ]]; then
  oc annotate storageclass standard-csi storageclass.kubernetes.io/is-default-class-
  oc annotate storageclass ssd-csi storageclass.kubernetes.io/is-default-class=true
fi

# Start CPU manager only for templates which require it.
if [[ $TARGET =~ rhel7.* ]] || [[ $TARGET =~ rhel8.* ]] || [[ $TARGET =~ fedora.* ]] || [[ $TARGET =~ windows2.* ]]; then
  oc label machineconfigpool worker custom-kubelet=enabled
  oc create -f - <<EOF
---
apiVersion: machineconfiguration.openshift.io/v1
kind: KubeletConfig
metadata:
  name: custom-config 
spec:
  machineConfigPoolSelector:
    matchLabels:
      custom-kubelet: enabled
  kubeletConfig: 
    cpuManagerPolicy: static
    reservedSystemCPUs: "2"
EOF

  oc wait --for=condition=Updating --timeout=300s machineconfigpool worker
  # it can take a while to enable CPU manager
  oc wait --for=condition=Updated --timeout=900s machineconfigpool worker
fi

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

oc patch kubevirt kubevirt -n $namespace --type merge -p '{"spec":{"configuration":{"developerConfiguration":{"featureGates": ["DataVolumes", "CPUManager", "NUMA", "DownwardMetrics"]}}}}'

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
oc apply -f https://github.com/kubevirt/containerized-data-importer/releases/download/$CDI_VERSION/cdi-operator.yaml
oc apply -f https://github.com/kubevirt/containerized-data-importer/releases/download/$CDI_VERSION/cdi-cr.yaml

oc patch cdi cdi -n cdi --patch '{"spec": {"config": {"dataVolumeTTLSeconds": -1}}}' --type merge

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

if [[ $TARGET =~ windows.* ]]; then
  ./automation/test-windows.sh $TARGET
else
  ./automation/test-linux.sh $TARGET
fi
