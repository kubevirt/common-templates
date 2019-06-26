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

readonly TEMPLATES_SERVER="https://templates.ovirt.org/kubevirt/"

export RHEL_NFS_DIR=${RHEL_NFS_DIR:-/var/lib/stdci/shared/kubevirt-images/rhel}
export RHEL_LOCK_PATH=${RHEL_LOCK_PATH:-/var/lib/stdci/shared/download_rhel_image.lock}
export WINDOWS_NFS_DIR=${WINDOWS_NFS_DIR:-/var/lib/stdci/shared/kubevirt-images/windows2016}
export WINDOWS_LOCK_PATH=${WINDOWS_LOCK_PATH:-/var/lib/stdci/shared/download_windows_image.lock}
export KUBEVIRT_MEMORY_SIZE=16384M
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

export VERSION=$(_curl https://api.github.com/repos/kubevirt/kubevirt/tags| jq -r '.[].name' | sort -r | head -1 )

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
    safe_download "$RHEL_LOCK_PATH" "$rhel_image_url" "$rhel_image" || exit 1

    # Hack to correctly set rhel nfs directory for kubevirt
    # https://github.com/kubevirt/kubevirt/blob/master/cluster/ephemeral-provider-common.sh#L38
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

  if [[ $TARGET =~ windows10.* ]]; then
    win_image_url="${TEMPLATES_SERVER}/win_10.qcow2"
  fi


  # Download Windows image
  win_image="$WINDOWS_NFS_DIR/disk.img"
  safe_download "$WINDOWS_LOCK_PATH" "$win_image_url" "$win_image" || exit 1
fi

_oc() { cluster/kubectl.sh "$@"; }

git submodule update --init

make -C osinfo-db/ OSINFO_DB_EXPORT=echo
ansible-playbook generate-templates.yaml

cp automation/connect_to_rhel_console.exp automation/kubevirt/connect_to_rhel_console.exp 
  
cd automation/kubevirt

curl -Lo virtctl \
    https://github.com/kubevirt/kubevirt/releases/download/$VERSION/virtctl-$VERSION-linux-amd64
chmod +x virtctl


export NAMESPACE="${NAMESPACE:-kubevirt}"

# Make sure that the VM is properly shut down on exit
trap '{ make cluster-down; }' EXIT SIGINT SIGTERM SIGSTOP


# Check if we are on a pull request in jenkins.
export KUBEVIRT_CACHE_FROM=${PULL_BASE_REF}
if [ -n "${KUBEVIRT_CACHE_FROM}" ]; then
    make pull-cache
fi

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

_oc apply -f https://github.com/kubevirt/kubevirt/releases/download/${VERSION}/kubevirt-operator.yaml
_oc apply -f https://github.com/kubevirt/kubevirt/releases/download/${VERSION}/kubevirt-cr.yaml

# OpenShift is running important containers under default namespace
namespaces=(kubevirt default)
if [[ $NAMESPACE != "kubevirt" ]]; then
  namespaces+=($NAMESPACE)
fi

timeout=300
sample=30

for i in ${namespaces[@]}; do
  # Wait until kubevirt pods are running
  current_time=0
  while [ -n "$(_oc get pods -n $i --no-headers | grep -v Running)" ]; do
    echo "Waiting for kubevirt pods to enter the Running state ..."
    _oc get pods -n $i --no-headers | >&2 grep -v Running || true
    sleep $sample

    current_time=$((current_time + sample))
    if [ $current_time -gt $timeout ]; then
      exit 1
    fi
  done

  # Make sure all containers are ready
  current_time=0
  while [ -n "$(_oc get pods -n $i -o'custom-columns=status:status.containerStatuses[*].ready' --no-headers | grep false)" ]; do
    echo "Waiting for KubeVirt containers to become ready ..."
    _oc get pods -n $i -o'custom-columns=status:status.containerStatuses[*].ready' --no-headers | grep false || true
    sleep $sample

    current_time=$((current_time + sample))
    if [ $current_time -gt $timeout ]; then
      exit 1
    fi
  done
  _oc get pods -n $i
done

#switch back original target
export TARGET=$original_target


if [[ $TARGET =~ rhel.* ]]; then
  ../test-rhel.sh $TARGET
fi

if [[ $TARGET =~ windows.* ]]; then
  ../test-windows.sh
fi
