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

export RHEL_NFS_DIR=${RHEL_NFS_DIR:-/var/lib/stdci/shared/kubevirt-images/$TARGET}
export lock_name="download_${TARGET}_image.lock"
export RHEL_LOCK_PATH=${RHEL_LOCK_PATH:-/var/lib/stdci/shared/$lock_name}
export WINDOWS_NFS_DIR=${WINDOWS_NFS_DIR:-/var/lib/stdci/shared/kubevirt-images/$TARGET}
export WINDOWS_LOCK_PATH=${WINDOWS_LOCK_PATH:-/var/lib/stdci/shared/$lock_name}
export KUBEVIRT_MEMORY_SIZE=19384M
export KUBEVIRT_PROVIDER="os-3.11.0"

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
export KUBEVIRT_VERSION=v0.27.0

wait_for_download_lock() {
  local max_lock_attempts=60
  local lock_wait_interval=60

  for ((i = 0; i < $max_lock_attempts; i++)); do
      if (set -o noclobber; > $1) 2> /dev/null; then
          echo "Acquired lock: $1"
          return
      fi
      sleep $lock_wait_interval
  done
  echo "Timed out waiting for lock: $1" >&2
  exit 1
}

safe_download() (
    # Download files into shared locations using a lock.
    # The lock will be released as soon as this subprocess will exit
    local lockfile="${1:?Lockfile was not specified}"
    local download_from="${2:?Download from was not specified}"
    local download_to="${3:?Download to was not specified}"
    local timeout_sec="${4:-3600}"

    touch "$lockfile"
    exec {fd}< "$lockfile"
    flock -e  -w "$timeout_sec" "$fd" || {
        echo "ERROR: Timed out after $timeout_sec seconds waiting for lock" >&2
        exit 1
    }

    local remote_sha1_url="${download_from}.sha1"
    local local_sha1_file="${download_to}.sha1"
    local remote_sha1
    local retry=3
    # Remote file includes only sha1 w/o filename suffix
    for i in $(seq 1 $retry);
    do
      remote_sha1="$(curl -s "${remote_sha1_url}")"
      if [[ "$remote_sha1" != "" ]]; then
        break
      fi
    done

    if [[ "$(cat "$local_sha1_file")" != "$remote_sha1" ]]; then
        echo "${download_to} is not up to date, corrupted or doesn't exist."
        echo "Downloading file from: ${remote_sha1_url}"
        curl "$download_from" --output "$download_to"
        sha1sum "$download_to" | cut -d " " -f1 > "$local_sha1_file"
        [[ "$(cat "$local_sha1_file")" == "$remote_sha1" ]] || {
            echo "${download_to} is corrupted"
            return 1
        }
    else
        echo "${download_to} is up to date"
    fi
)

original_target=$TARGET
image_path=""
if [[ $TARGET =~ rhel.* ]]; then
    # Create images directory
    if [[ ! -d $RHEL_NFS_DIR ]]; then
        mkdir -p $RHEL_NFS_DIR
    fi

    rhel_image_url=""

    if [[ $TARGET =~ rhel6.* ]]; then
      rhel_image_url="${TEMPLATES_SERVER}/rhel6.qcow2"
    fi

    if [[ $TARGET =~ rhel7.* ]]; then
      rhel_image_url="${TEMPLATES_SERVER}/rhel7.img"
    fi

    if [[ $TARGET =~ rhel8.* ]]; then
      rhel_image_url="${TEMPLATES_SERVER}/rhel8.qcow2"
    fi

    # Download RHEL image
    rhel_image="$RHEL_NFS_DIR/disk.img"
    image_path=$rhel_image
    safe_download "$RHEL_LOCK_PATH" "$rhel_image_url" "$rhel_image" || exit 1
    # Hack to correctly set rhel nfs directory for kubevirtci
    # https://github.com/kubevirt/kubevirtci/blob/master/cluster-up/cluster/ephemeral-provider-common.sh#L33
    export TARGET="os-3.11.0"
fi

if [[ $TARGET =~ windows.* ]]; then
  # Create images directory
  if [[ ! -d $WINDOWS_NFS_DIR ]]; then
    mkdir -p $WINDOWS_NFS_DIR
  fi

  win_image_url=""

  if [[ $TARGET =~ windows2012.* ]]; then
    win_image_url="${TEMPLATES_SERVER}/win_12.qcow2"
  fi

  if [[ $TARGET =~ windows2016.* ]]; then
    win_image_url="${TEMPLATES_SERVER}/win_16.img"
  fi

  if [[ $TARGET =~ windows2019.* ]]; then
    win_image_url="${TEMPLATES_SERVER}/win_19_2.qcow2"
  fi

  if [[ $TARGET =~ windows10.* ]]; then
    win_image_url="${TEMPLATES_SERVER}/win_10.qcow2"
  fi


  # Download Windows image
  win_image="$WINDOWS_NFS_DIR/disk.img"
  image_path=$win_image
  safe_download "$WINDOWS_LOCK_PATH" "$win_image_url" "$win_image" || exit 1
fi

_oc() { cluster-up/kubectl.sh "$@"; }

git submodule update --init

make generate

cp automation/connect_to_rhel_console.exp automation/kubevirtci/connect_to_rhel_console.exp
  
cd automation/kubevirtci

curl -Lo virtctl \
    https://github.com/kubevirt/kubevirt/releases/download/$KUBEVIRT_VERSION/virtctl-$KUBEVIRT_VERSION-linux-amd64
chmod +x virtctl


export NAMESPACE="${NAMESPACE:-kubevirt}"

# Make sure that the VM is properly shut down on exit
trap '{ make cluster-down; rm -rf ../kubevirt-template-validator; }' EXIT SIGINT SIGTERM SIGSTOP


make cluster-down
make cluster-up

# Wait for nodes to become ready
set +e
_oc get nodes --no-headers
oc_rc=$?
while [ $oc_rc -ne 0 ] || [ -n "$(_oc get nodes --no-headers | grep NotReady)" ]; do
    echo "Waiting for all nodes to become ready ..."
    _oc get nodes --no-headers
    oc_rc=$?
    sleep 10
done
set -e

echo "Nodes are ready:"
_oc get nodes

_oc apply -f https://github.com/kubevirt/kubevirt/releases/download/${KUBEVIRT_VERSION}/kubevirt-operator.yaml
_oc apply -f https://github.com/kubevirt/kubevirt/releases/download/${KUBEVIRT_VERSION}/kubevirt-cr.yaml


_oc create namespace openshift-cnv-base-images
_oc project kubevirt
_oc create -f - <<EOF
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: kubevirt-config
  namespace: kubevirt
data:
  feature-gates: "DataVolumes"
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: cdi-role
rules:
- apiGroups: ["cdi.kubevirt.io"]
  resources: ["datavolumes/source"]
  verbs: ["*"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: kubevirt-cdi
  namespace: openshift-cnv-base-images
subjects:
- kind: ServiceAccount
  name: default
  namespace: kubevirt
roleRef:
  kind: ClusterRole
  name: cdi-role
  apiGroup: rbac.authorization.k8s.io
EOF

echo "Deploying CDI"
export CDI_VERSION=$(curl -s https://github.com/kubevirt/containerized-data-importer/releases/latest | grep -o "v[0-9]\.[0-9]*\.[0-9]*")
_oc create -f https://github.com/kubevirt/containerized-data-importer/releases/download/$CDI_VERSION/cdi-operator.yaml
_oc create -f https://github.com/kubevirt/containerized-data-importer/releases/download/$CDI_VERSION/cdi-cr.yaml
_oc rollout status -n cdi deployment/cdi-operator

# Deploy template validator (according to https://github.com/kubevirt/kubevirt-template-validator/blob/master/README.md)
echo "Deploying template validator"

VALIDATOR_VERSION=$(_curl https://api.github.com/repos/kubevirt/kubevirt-template-validator/tags| jq -r '.[].name' | sort -r | head -1 )
rm -rf ../kubevirt-template-validator
git clone -b ${VALIDATOR_VERSION} --depth 1 https://github.com/kubevirt/kubevirt-template-validator ../kubevirt-template-validator

_oc apply -f ../kubevirt-template-validator/cluster/okd/manifests/template-view-role.yaml

sed "s|image:.*|image: quay.io/kubevirt/kubevirt-template-validator:${VALIDATOR_VERSION}|" < ../kubevirt-template-validator/cluster/okd/manifests/service.yaml | \
	sed "s|imagePullPolicy: Always|imagePullPolicy: IfNotPresent|g" | \
	_oc apply -f -

# Wait for the validator deployment to be ready
_oc rollout status deployment/virt-template-validator -n $NAMESPACE

# Apply templates
echo "Deploying templates"
_oc apply -n kubevirt -f ../../dist/templates

namespaces=(kubevirt)
if [[ $NAMESPACE != "kubevirt" ]]; then
  namespaces+=($NAMESPACE)
fi

timeout=300
sample=30

# Waiting for kubevirt cr to report available
_oc wait --for=condition=Available --timeout=${timeout}s kubevirt/kubevirt -n $NAMESPACE

# Ignoring the 'registry-console' pod. It will be in a failed state, but it is not relevant for this test
# https://github.com/openshift/openshift-ansible/issues/12115
ignored_pods='registry-console'

for i in ${namespaces[@]}; do
  # Make sure all containers are ready
  current_time=0
  custom_columns='name:metadata.name,status:status.containerStatuses[*].ready'

  while [ -n "$(_oc get pods -n $i -o"custom-columns=${custom_columns}" --no-headers | grep -v ${ignored_pods} | grep false)" ]; do
    echo "Waiting for pods to become ready ..."
    _oc get pods -n $i -o"custom-columns=${custom_columns}" --no-headers | grep -v ${ignored_pods} | grep false || true
    sleep $sample

    current_time=$((current_time + sample))
    if [ $current_time -gt $timeout ]; then
      exit 1
    fi
  done
  _oc get pods -n $i
done

# Used to store the exit code of the webhook creation command
webhookUpdated=1
webhookUpdateRetries=10

while [ $webhookUpdated != 0 ];
do
  # Approve all CSRs to avoid an issue similar to this: https://github.com/kubernetes/frakti/issues/200
  # This is attempted before any call to 'oc exec' because there's suspect that more csr's have to be approved
  # over time and not only once after the cluster has been initiated.
  _oc adm certificate approve $(_oc get csr -ocustom-columns=NAME:metadata.name --no-headers)

  if [ $webhookUpdateRetries == 0 ];
  then
    echo Retry count for template validator ca bundle injection reached
    exit 1
  fi

  webhookUpdateRetries=$((webhookUpdateRetries-1))

  VALIDATOR_POD=$(_oc get pod -n $NAMESPACE -l kubevirt.io=virt-template-validator -o json | jq -r .items[0].metadata.name)
  if [ "$VALIDATOR_POD" == "" ];
  then
    # Retry if an error occured
    continue
  fi

  CA_BUNDLE=$(_oc exec -n $NAMESPACE $VALIDATOR_POD -- /bin/cat /var/run/secrets/kubernetes.io/serviceaccount/service-ca.crt | base64 -w 0)
  if [ "$CA_BUNDLE" == "" ];
  then
    # Retry if an error occured
    continue
  fi

  sed "s/\${CA_BUNDLE}/${CA_BUNDLE}/g" < ../kubevirt-template-validator/cluster/okd/manifests/validating-webhook.yaml | _oc apply -f -

  # If the webhook failed to be created, retry
  webhookUpdated=$?
done

_oc describe validatingwebhookconfiguration virt-template-validator

#switch back original target
export TARGET=$original_target

if [[ $TARGET =~ rhel.* ]]; then
  ../test-rhel.sh $TARGET $image_path
fi

if [[ $TARGET =~ windows.* ]]; then
  ../test-windows.sh $TARGET $image_path
fi
