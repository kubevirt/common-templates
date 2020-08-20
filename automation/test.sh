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

sudo dnf install -y jq ansible libosinfo python-gobject libosinfo intltool

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

export KUBEVIRT_VERSION=$(_curl https://api.github.com/repos/kubevirt/kubevirt/tags| jq -r '.[].name' | sort -r | head -1 )

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
    local download_from="${1:?Download from was not specified}"
    local download_to="disk.img"
    local timeout_sec="${2:-3600}"

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
case "$TARGET" in
"fedora")
	curl -fL -o "disk.img" https://download.fedoraproject.org/pub/fedora/linux/releases/30/Cloud/x86_64/images/Fedora-Cloud-Base-30-1.2.x86_64.qcow2
    ;;
esac

if [[ $TARGET =~ rhel.* ]]; then
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
    safe_download "$rhel_image_url" || exit 1
    # Hack to correctly set rhel nfs directory for kubevirtci
    # https://github.com/kubevirt/kubevirtci/blob/master/cluster-up/cluster/ephemeral-provider-common.sh#L33
fi

if [[ $TARGET =~ windows.* ]]; then
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
  safe_download "$win_image_url" || exit 1
fi

git submodule update --init

make generate

#set terminationGracePeriodSeconds to 0
for filename in dist/templates/*; do
    sed -i -e 's/^\(\s*terminationGracePeriodSeconds\s*:\s*\).*/\10/' $filename
done

cp automation/connect_to_rhel_console.exp automation/kubevirtci/connect_to_rhel_console.exp
  
curl -Lo virtctl \
    https://github.com/kubevirt/kubevirt/releases/download/$KUBEVIRT_VERSION/virtctl-$KUBEVIRT_VERSION-linux-amd64
chmod +x virtctl


export NAMESPACE="${NAMESPACE:-kubevirt}"

# Make sure that the VM is properly shut down on exit
trap '{ rm -rf ../kubevirt-template-validator; }' EXIT SIGINT SIGTERM SIGSTOP


# Wait for nodes to become ready
set +e
oc get nodes --no-headers
oc_rc=$?
while [ $oc_rc -ne 0 ] || [ -n "$(oc get nodes --no-headers | grep NotReady)" ]; do
    echo "Waiting for all nodes to become ready ..."
    oc get nodes --no-headers
    oc_rc=$?
    sleep 10
done
set -e

echo "Nodes are ready:"
oc get nodes

oc apply -f https://github.com/kubevirt/kubevirt/releases/download/${KUBEVIRT_VERSION}/kubevirt-operator.yaml
oc apply -f https://github.com/kubevirt/kubevirt/releases/download/${KUBEVIRT_VERSION}/kubevirt-cr.yaml

# Deploy template validator (according to https://github.com/kubevirt/kubevirt-template-validator/blob/master/README.md)
echo "Deploying template validator"

VALIDATOR_VERSION=$(_curl https://api.github.com/repos/kubevirt/kubevirt-template-validator/tags| jq -r '.[].name' | sort -r | head -1 )
rm -rf ../kubevirt-template-validator
git clone -b ${VALIDATOR_VERSION} --depth 1 https://github.com/kubevirt/kubevirt-template-validator ../kubevirt-template-validator

oc apply -f ../kubevirt-template-validator/cluster/okd/manifests/template-view-role.yaml

sed "s|image:.*|image: quay.io/kubevirt/kubevirt-template-validator:${VALIDATOR_VERSION}|" < ../kubevirt-template-validator/cluster/okd/manifests/service.yaml | \
	sed "s|imagePullPolicy: Always|imagePullPolicy: IfNotPresent|g" | \
	oc apply -f -

# Wait for the validator deployment to be ready
oc rollout status deployment/virt-template-validator -n $NAMESPACE

# Apply templates
echo "Deploying templates"
oc apply -n default -f ../../dist/templates

namespaces=(kubevirt)
if [[ $NAMESPACE != "kubevirt" ]]; then
  namespaces+=($NAMESPACE)
fi

timeout=300
sample=30

# Waiting for kubevirt cr to report available
oc wait --for=condition=Available --timeout=${timeout}s kubevirt/kubevirt -n $NAMESPACE

for i in ${namespaces[@]}; do
  # Make sure all containers are ready
  current_time=0
  custom_columns='name:metadata.name,status:status.containerStatuses[*].ready'

  while [ -n "$(oc get pods -n $i -o"custom-columns=${custom_columns}" --no-headers | grep false)" ]; do
    echo "Waiting for pods to become ready ..."
    oc get pods -n $i -o"custom-columns=${custom_columns}" --no-headers | grep false || true
    sleep $sample

    current_time=$((current_time + sample))
    if [ $current_time -gt $timeout ]; then
      exit 1
    fi
  done
  oc get pods -n $i
done

# Used to store the exit code of the webhook creation command
webhookUpdated=1
webhookUpdateRetries=10

while [ $webhookUpdated != 0 ];
do
  # Approve all CSRs to avoid an issue similar to this: https://github.com/kubernetes/frakti/issues/200
  # This is attempted before any call to 'oc exec' because there's suspect that more csr's have to be approved
  # over time and not only once after the cluster has been initiated.
  oc adm certificate approve $(oc get csr -ocustom-columns=NAME:metadata.name --no-headers)

  if [ $webhookUpdateRetries == 0 ];
  then
    echo Retry count for template validator ca bundle injection reached
    exit 1
  fi

  webhookUpdateRetries=$((webhookUpdateRetries-1))

  VALIDATOR_POD=$(oc get pod -n $NAMESPACE -l kubevirt.io=virt-template-validator -o json | jq -r .items[0].metadata.name)
  if [ "$VALIDATOR_POD" == "" ];
  then
    # Retry if an error occured
    continue
  fi

  CA_BUNDLE=$(oc exec -n $NAMESPACE $VALIDATOR_POD -- /bin/cat /var/run/secrets/kubernetes.io/serviceaccount/service-ca.crt | base64 -w 0)
  if [ "$CA_BUNDLE" == "" ];
  then
    # Retry if an error occured
    continue
  fi

  sed "s/\${CA_BUNDLE}/${CA_BUNDLE}/g" < ../kubevirt-template-validator/cluster/okd/manifests/validating-webhook.yaml | oc apply -f -

  # If the webhook failed to be created, retry
  webhookUpdated=$?
done

oc describe validatingwebhookconfiguration virt-template-validator

if [[ $TARGET =~ rhel.* ]]; then
  ../test-rhel.sh $TARGET
fi

if [[ $TARGET =~ windows.* ]]; then
  ../test-windows.sh $TARGET
fi
