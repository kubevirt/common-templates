#!/bin/bash

set -ex

template_name="windows"
# Prepare PV and PVC for Windows testing

oc create -f - <<EOF
---
apiVersion: v1
kind: PersistentVolume
metadata:
  name: disk-win
  labels:
    kubevirt.io/os: "windows"
spec:
  capacity:
    storage: 50Gi
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
      storage: 50Gi

  selector:
    matchLabels:
      kubevirt.io/os: "windows"
---
EOF

oc create -f - <<EOF
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

timeout=1000
sample=30

# Make sure winrmcli pod is ready
set +e
current_time=0
while [ $(oc get pod winrmcli -o json | jq -r '.status.phase') != "Running" ]  ; do 
  oc get pod winrmcli -o yaml
  current_time=$((current_time + sample))
  if [ $current_time -gt $timeout ]; then
    exit 1
  fi
  sleep $sample;
done
set -e

oc exec -it winrmcli -- yum install -y iproute iputils net-tools arp-scan

kubeconfig=$( cluster-up/kubeconfig.sh )

sizes=("medium" "large")
workloads=("server")

if [[ $TARGET =~ windows10.* ]]; then
  template_name="windows10"
  workloads=("desktop")
fi

delete_vm(){
  vm_name=$1
  local template_name=$2
  set +e
  #stop vm
  ./virtctl --kubeconfig=$kubeconfig stop $vm_name
  #delete vm
  oc process -o json $template_name NAME=$vm_name PVCNAME=disk-win | \
  oc delete -f -
  set -e
}

run_vm(){
  vm_name=$1
  template_path="../../dist/templates/$vm_name.yaml"
  local template_name=$( oc get -f ${template_path} -o=custom-columns=NAME:.metadata.name --no-headers )
  running=false

  #If first try fails, it tries 2 more time to run it, before it fails whole test
  for i in `seq 1 3`; do
    error=false

    # windows 2019 doesn't support rtc timer. 
    if [[ $TARGET =~ windows2019.* ]]; then
      oc process -o json $template_name NAME=$vm_name PVCNAME=disk-win | \
      jq '.items[0].spec.template.spec.volumes[0]+= {"ephemeral": {"persistentVolumeClaim": {"claimName": "disk-win"}}} | 
      del(.items[0].spec.template.spec.volumes[0].persistentVolumeClaim) | del(.items[0].spec.template.spec.domain.clock.timer.rtc) |
      .items[0].metadata.labels["vm.kubevirt.io/template.namespace"]="default"' | \
      oc apply -f -
    else
      oc process -o json $template_name NAME=$vm_name PVCNAME=disk-win | \
      jq '.items[0].spec.template.spec.volumes[0]+= {"ephemeral": {"persistentVolumeClaim": {"claimName": "disk-win"}}} | 
      del(.items[0].spec.template.spec.volumes[0].persistentVolumeClaim) |
      .items[0].metadata.labels["vm.kubevirt.io/template.namespace"]="default"' | \
      oc apply -f -
    fi

    validator_pods=($(oc get pods -n kubevirt -l kubevirt.io=virt-template-validator -ocustom-columns=name:metadata.name --no-headers))

    for pod in ${validator_pods[@]}; do
      oc logs -n kubevirt $pod
    done

    # start vm
    ./virtctl --kubeconfig=$kubeconfig start $vm_name

    set +e
    current_time=0
    while [ $(oc get vmi $vm_name -o json | jq -r '.status.phase') != Running ] ; do 
      oc describe vmi $vm_name
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
      delete_vm $vm_name $template_name
      #jump to next iteration and try to run vm again
      continue
    fi

    oc describe vm $vm_name
    oc describe vmi $vm_name

    # get ip address of vm
    ipAddressVMI=$(oc get vmi $vm_name -o json| jq -r '.status.interfaces[0].ipAddress')

    set +e
    pod_name=$(oc get pods | egrep -i '*virt-launcher*' | cut -d " " -f1)
    current_time=0
    # run ipconfig /all command on windows vm
    while [[ $(oc exec -it winrmcli -- ./usr/bin/winrm-cli -hostname $ipAddressVMI -port 5985 -username "Administrator" -password "Heslo123" "ipconfig /all" | grep "IPv4 Address" | wc -l ) -eq 0 ]] ; do 

      current_time=$((current_time + 30))
      if [[ $current_time -gt $timeout ]]; then
        error=true
        break
      fi
      sleep 30;
    done
    set -e

    delete_vm $vm_name $template_name
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
