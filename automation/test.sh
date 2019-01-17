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

export TARGET="windows2016"
export WINDOWS_NFS_DIR=${WINDOWS_NFS_DIR:-/var/lib/stdci/shared/kubevirt-images/windows2016}
export WINDOWS_LOCK_PATH=${WINDOWS_LOCK_PATH:-/var/lib/stdci/shared/download_windows_image.lock}
export KUBEVIRT_MEMORY_SIZE=12288M

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
    # Remote file includes only sha1 w/o filename suffix
    remote_sha1="$(curl -s "${remote_sha1_url}")"
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


# Create images directory
if [[ ! -d $WINDOWS_NFS_DIR ]]; then
  mkdir -p $WINDOWS_NFS_DIR
fi

readonly TEMPLATES_SERVER="https://templates.ovirt.org/kubevirt/"
win_image_url="${TEMPLATES_SERVER}/win01.img"
win_image="$WINDOWS_NFS_DIR/disk.img"
# Download Windows image
safe_download "$WINDOWS_LOCK_PATH" "$win_image_url" "$win_image" || exit 1


_oc() { 
  cluster/kubectl.sh "$@"
}

git submodule update --init

ansible-playbook generate-templates.yaml
  
cd automation/kubevirt

# Make sure that the VM is properly shut down on exit
trap '{ make cluster-down; }' EXIT SIGINT SIGTERM SIGSTOP

# If run on CI use random kubevirt system-namespaces
if [ -n "${JOB_NAME}" ]; then
  export NAMESPACE="kubevirt-$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 10 | head -n 1)"
  cat >hack/config-local.sh <<EOF
namespace=${NAMESPACE}
EOF
else
  export NAMESPACE="${NAMESPACE:-kubevirt}"
fi

export KUBEVIRT_PROVIDER="os-3.11.0"
export VERSION="v0.13.0"

curl -Lo virtctl \
    https://github.com/kubevirt/kubevirt/releases/download/$VERSION/virtctl-$VERSION-linux-amd64
chmod +x virtctl

make cluster-down
make cluster-up 

# Wait for nodes to become ready
_oc get nodes --no-headers
set +e
kubectl_rc=$?
while [ $kubectl_rc -ne 0 ] || [ -n "$(_oc get nodes --no-headers | grep NotReady)" ]; do
    echo "Waiting for all nodes to become ready ..."
    _oc get nodes --no-headers
    kubectl_rc=$?
    sleep 10
done
set -e

echo "Nodes are ready:"
_oc get nodes

_oc describe nodes

_oc adm policy add-scc-to-user privileged system:serviceaccount:kubevirt:kubevirt-privileged
_oc adm policy add-scc-to-user privileged system:serviceaccount:kubevirt:kubevirt-controller
_oc adm policy add-scc-to-user privileged system:serviceaccount:kubevirt:kubevirt-apiserver

_oc create \
    -f https://github.com/kubevirt/kubevirt/releases/download/$VERSION/kubevirt.yaml

export NAMESPACE="${NAMESPACE:-kubevirt}"
# OpenShift is running important containers under default namespace
namespaces=(kubevirt default)
if [[ $NAMESPACE != "kubevirt" ]]; then
  namespaces+=($NAMESPACE)
fi

sample=30
timeout=300

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

# Prepare PV and PVC for Windows testing, create winrmcli pod

_oc create -f - <<EOF
---
apiVersion: v1
kind: PersistentVolume
metadata:
  name: disk-windows
  labels:
    kubevirt.io/os: "windows"
spec:
  capacity:
    storage: 30Gi
  accessModes:
    - ReadWriteOnce
  nfs:
    server: "nfs"
    path: /
  storageClassName: local
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: disk-windows
  labels:
    kubevirt.io: ""
spec:
  storageClassName: local
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 30Gi

  selector:
    matchLabels:
      kubevirt.io/os: "windows"
---
apiVersion: v1
kind: Pod
metadata:
  name: winrmcli
  namespace: default
spec:
  containers:
  - image: kubevirt/winrmcli
    command:
      - sleep
      - "3600"
    imagePullPolicy: Always
    name: winrmcli
restartPolicy: Always
EOF

# Make sure winrmcli pod is ready
set +e
current_time=0
while [[ $(_oc get pod winrmcli -o json | jq '.status.phase') != *Running* ]]  ; do 
  _oc get pod winrmcli -o yaml
  current_time=$((current_time + sample))
  if [ $current_time -gt $timeout ]; then
    exit 1
  fi
  sleep $sample;
done
set -e

_oc exec -it winrmcli -- yum install -y iproute iputils

kubeconfig="cluster/$KUBEVIRT_PROVIDER/.kubeconfig"
sizes=("medium" "large")
for size in ${sizes[@]}; do
  windowsTemplatePath="../../dist/templates/win2k12r2-generic-$size.yaml"

  _oc process -o json --local -f $windowsTemplatePath NAME=win2k1r2-$size PVCNAME=disk-windows | \
  jq '.items[0].spec.template.spec.volumes[0]+= {"ephemeral": {"persistentVolumeClaim": {"claimName": "disk-windows"}}} | 
  del(.items[0].spec.template.spec.volumes[0].persistentVolumeClaim)' | \
  _oc apply -f -

  # start vm
  ./virtctl --kubeconfig=$kubeconfig start win2k1r2-$size

  set +e
  current_time=0
  while [[ $(_oc get vmi win2k1r2-$size -o json | jq '.status.phase') != *Running* ]] ; do 
    _oc describe vmi win2k1r2-$size
    current_time=$((current_time + sample))
    if [ $current_time -gt $timeout ]; then
      exit 1
    fi
    sleep $sample;
  done
  set -e

  _oc describe vm win2k1r2-$size
  _oc describe vmi win2k1r2-$size

  # get ip address of vm
  ipAddressVMI=$(_oc get vmi win2k1r2-$size -o yaml | grep ipAddress | awk '{print $3}')

  set +e
  timeout=600
  current_time=0
  # Make sure vm is ready
  while _oc exec -it winrmcli -- ping -c1 $ipAddressVMI| grep "Destination Host Unreachable" ; do 
    current_time=$((current_time + 10))
    if [ $current_time -gt $timeout ]; then
      exit 1
    fi
    sleep 10;
  done

  timeout=300
  current_time=0
  # run ipconfig /all command on windows vm
  while [[ $(_oc exec -it winrmcli -- ./usr/bin/winrm-cli -hostname $ipAddressVMI -port 5985 -username "Administrator" -password "Heslo123" "ipconfig /all") != *"$ipAddressVMI"* ]] ; do 
    current_time=$((current_time + 10))
    if [ $current_time -gt $timeout ]; then
      exit 1
    fi
    sleep 10;
  done

  ./virtctl --kubeconfig=$kubeconfig stop win2k1r2-$size 
  set -e

  _oc process -o json --local -f $windowsTemplatePath NAME=win2k1r2-$size PVCNAME=disk-windows | \
  jq '.items[0].spec.template.spec.volumes[0]+= {"ephemeral": {"persistentVolumeClaim": {"claimName": "disk-windows"}}} | 
  del(.items[0].spec.template.spec.volumes[0].persistentVolumeClaim)' | \
  _oc delete -f -
done
