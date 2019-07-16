#!/bin/bash

set -ex

_oc() { 
  cluster-up/kubectl.sh "$@"
}

template_name="win2k12r2"
# Prepare PV and PVC for Windows testing

_oc create -f - <<EOF
---
apiVersion: v1
kind: PersistentVolume
metadata:
  name: disk-win
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
  name: disk-win
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
EOF

_oc create -f - <<EOF
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
---
EOF

timeout=600
sample=30

# Make sure winrmcli pod is ready
set +e
current_time=0
while [ $(_oc get pod winrmcli -o json | jq -r '.status.phase') != "Running" ]  ; do 
  _oc get pod winrmcli -o yaml
  current_time=$((current_time + sample))
  if [ $current_time -gt $timeout ]; then
    exit 1
  fi
  sleep $sample;
done
set -e

_oc exec -it winrmcli -- yum install -y iproute iputils

kubeconfig=$( cluster-up/kubeconfig.sh )

sizes=("medium" "large")
workloads=("server" "desktop")

pwd
for size in ${sizes[@]}; do
  for workload in ${workloads[@]}; do
    templatePath="../../dist/templates/$template_name-$workload-$size.yaml"

    _oc process -o json --local -f $templatePath NAME=$template_name-$workload-$size PVCNAME=disk-win | \
    jq '.items[0].spec.template.spec.volumes[0]+= {"ephemeral": {"persistentVolumeClaim": {"claimName": "disk-win"}}} | 
    del(.items[0].spec.template.spec.volumes[0].persistentVolumeClaim)' | \
    _oc apply -f -

    # start vm
    ./virtctl --kubeconfig=$kubeconfig start $template_name-$workload-$size

    set +e
    current_time=0
    while [ $(_oc get vmi $template_name-$workload-$size -o json | jq -r '.status.phase') != Running ] ; do 
      _oc describe vmi $template_name-$workload-$size
      current_time=$((current_time + sample))
      if [ $current_time -gt $timeout ]; then
        exit 1
      fi
      sleep $sample;
    done
    set -e

    _oc describe vm $template_name-$workload-$size
    _oc describe vmi $template_name-$workload-$size

    # get ip address of vm
    ipAddressVMI=$(_oc get vmi $template_name-$workload-$size -o json| jq -r '.status.interfaces[0].ipAddress')

    set +e
    current_time=0
    # run ipconfig /all command on windows vm
    while [[ $(_oc exec -it winrmcli -- ./usr/bin/winrm-cli -hostname $ipAddressVMI -port 5985 -username "Administrator" -password "Heslo123" "ipconfig /all") != *"$ipAddressVMI"* ]] ; do 
      current_time=$((current_time + 10))
      if [[ $current_time -gt $timeout ]]; then
        exit 1
      fi
      sleep 10;
    done

    ./virtctl --kubeconfig=$kubeconfig stop $template_name-$workload-$size 
    set -e

    _oc process -o json --local -f $templatePath NAME=$template_name-$workload-$size PVCNAME=disk-$template_name | \
    _oc delete -f -
  done
done
