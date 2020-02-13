#!/bin/bash

set -ex

_oc() { 
  cluster-up/kubectl.sh "$@"
}

template_name=$1
# Prepare PV and PVC for rhel8 testing

_oc create -f - <<EOF
---
apiVersion: v1
kind: PersistentVolume
metadata:
  name: disk-rhel
  labels:
    kubevirt.io/test: "rhel"
spec:
  capacity:
    storage: 30Gi
  accessModes:
    - ReadWriteOnce
  nfs:
    server: "nfs"
    path: /
  storageClassName: rhel
---
EOF

_oc create -f - <<EOF
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: disk-rhel
  labels:
    kubevirt.io: ""
spec:
  volumeName: disk-rhel
  storageClassName: rhel
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 30Gi

  selector:
    matchLabels:
      kubevirt.io/test: "rhel"
---
EOF

timeout=300
sample=10

kubeconfig=$( cluster-up/kubeconfig.sh )

sizes=("tiny" "small" "medium" "large")
workloads=("desktop" "server" "highperformance")

if [[ $TARGET =~ rhel6.* ]]; then
  workloads=("desktop" "server")
fi

delete_vm(){
  vm_name=$1
  template_path=$2
  set +e
  #stop vm
  ./virtctl --kubeconfig=$kubeconfig stop $vm_name
  #delete vm
  _oc process -o json --local -f $template_path NAME=$vm_name PVCNAME=disk-rhel | \
    _oc delete -f -
  set -e
}

run_vm(){
  vm_name=$1
  template_path="../../dist/templates/$vm_name.yaml"
  running=false

  #If first try fails, it tries 2 more time to run it, before it fails whole test
  for i in `seq 1 3`; do
    error=false
    _oc process -o json --local -f $template_path NAME=$vm_name PVCNAME=disk-rhel | \
    jq '.items[0].spec.template.spec.volumes[0]+= {"ephemeral": {"persistentVolumeClaim": {"claimName": "disk-rhel"}}} | 
    del(.items[0].spec.template.spec.volumes[0].persistentVolumeClaim)' | \
    _oc apply -f -

    # start vm
    ./virtctl --kubeconfig=$kubeconfig start $vm_name

    set +e
    current_time=0
    while [ $(_oc get vmi $vm_name -o json | jq -r '.status.phase') != Running ] ; do 
      _oc describe vmi $vm_name
      current_time=$((current_time + sample))
      if [ $current_time -gt $timeout ]; then
        error=true
        break
      fi
      sleep $sample;
    done
    set -e

    if $error ; then
      #delete vm
      delete_vm $vm_name $template_path
      #jump to next iteration and try to run vm again
      continue
    fi

    _oc describe vm $vm_name
    _oc describe vmi $vm_name

    set +e
    ./connect_to_rhel_console.exp $kubeconfig $vm_name
    if [ $? -ne 0 ] ; then 
      error=true
    fi
    set -e
  
    delete_vm $vm_name $template_path
    #no error were observed, the vm is running
    if ! $error ; then
      running=true
      break
    fi
  done

  if ! $running ; then
    exit 1 
  fi
}

for size in ${sizes[@]}; do
  for workload in ${workloads[@]}; do
    vm_name=$template_name-$workload-$size
    run_vm $vm_name
  done
done
