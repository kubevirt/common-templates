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

trap '{ release_download_lock $WINDOWS_LOCK_PATH; make cluster-down; }' EXIT SIGINT SIGTERM SIGSTOP

set -ex

export TARGET="windows2016"
export WINDOWS_NFS_DIR=${WINDOWS_NFS_DIR:-/var/lib/stdci/shared/kubevirt-images/windows2016}
export WINDOWS_LOCK_PATH=${WINDOWS_LOCK_PATH:-/var/lib/stdci/shared/download_windows_image.lock}

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

release_download_lock() { 
  if [[ -e "$1" ]]; then
    rm -f "$1"
    echo "Released lock: $1"
  fi
}

# Create images directory
if [[ ! -d $WINDOWS_NFS_DIR ]]; then
  mkdir -p $WINDOWS_NFS_DIR
fi

# Download Windows image
if wait_for_download_lock $WINDOWS_LOCK_PATH; then
  if [[ ! -f "$WINDOWS_NFS_DIR/disk.img" ]]; then
    curl http://templates.ovirt.org/kubevirt/win01.img > $WINDOWS_NFS_DIR/disk.img
  fi
  release_download_lock $WINDOWS_LOCK_PATH
else
  exit 1
fi

_oc() { 
  cluster/kubectl.sh "$@"
}

git submodule update --init

ansible-playbook generate-templates.yaml
  
cd automation/kubevirt

export KUBEVIRT_PROVIDER="os-3.10.0"
export VERSION=v0.9.1

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

_oc adm policy add-scc-to-user privileged system:serviceaccount:kube-system:kubevirt-privileged
_oc adm policy add-scc-to-user privileged system:serviceaccount:kube-system:kubevirt-controller
_oc adm policy add-scc-to-user privileged system:serviceaccount:kube-system:kubevirt-apiserver

_oc create \
    -f https://github.com/kubevirt/kubevirt/releases/download/$VERSION/kubevirt.yaml

export NAMESPACE="${NAMESPACE:-kube-system}"
# OpenShift is running important containers under default namespace
namespaces=(kube-system default)
if [[ $NAMESPACE != "kube-system" ]]; then
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
  # lower RAM size in windows template
  sed -i -e 's/4G/2G/g; s/8G/2G/g' $windowsTemplatePath

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
