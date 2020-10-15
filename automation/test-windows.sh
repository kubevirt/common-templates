#!/bin/bash

set -ex

namespace="kubevirt"
template_name="windows"

oc apply -n kubevirt -f - <<EOF
apiVersion: cdi.kubevirt.io/v1beta1
kind: DataVolume
metadata:
  name: ${TARGET}-datavolume-original
spec:
  source:
    registry:
      secretRef: common-templates-container-disk-puller
      url: "docker://quay.io/openshift-cnv/ci-common-templates-images:${TARGET}"
  pvc:
    accessModes:
      - ReadWriteOnce
    resources:
      requests:
        storage: 40Gi
EOF

oc apply -f - <<EOF
---
apiVersion: v1
kind: Pod
metadata:
  name: winrmcli
  namespace: kubevirt
spec:
  containers:
  - image: kubevirt/winrmcli
    command: ["/bin/sh","-c"]
    args: [ "yum install -y iproute iputils net-tools arp-scan; sleep 3000"]
    imagePullPolicy: Always
    name: winrmcli
restartPolicy: Always
---
EOF

timeout=1000
sample=10
current_time=0
#check if cdi import pod is running
while [ $(oc get pods -n $namespace | grep "${TARGET}-datavolume-original.*Running" | wc -l ) -eq 0 ] ; do 
  oc get pods -n $namespace
  current_time=$((current_time + sample))
  if [ $current_time -gt $timeout ]; then
    error=true
    break
  fi
  sleep $sample;
done

oc logs -n $namespace -f importer-${TARGET}-datavolume-original

# Make sure winrmcli pod is ready
set +e
current_time=0
while [ $(oc get pod winrmcli -o json -n $namespace | jq -r '.status.phase') != "Running" ]  ; do 
  oc get pod winrmcli -o yaml -n $namespace
  current_time=$((current_time + sample))
  if [ $current_time -gt $timeout ]; then
    exit 1
  fi
  sleep $sample;
done
set -e

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
  ./virtctl stop $vm_name -n $namespace
  #delete vm
  oc process -n $namespace -o json $template_name NAME=$vm_name SRC_PVC_NAME=$TARGET-datavolume-original SRC_PVC_NAMESPACE=kubevirt| \
  oc delete -f -
  set -e
}

run_vm(){
  vm_name=$1
  template_path="dist/templates/$vm_name.yaml"
  local template_name=$( oc get -n ${namespace} -f ${template_path} -o=custom-columns=NAME:.metadata.name --no-headers -n kubevirt )
  running=false

  #If first try fails, it tries 2 more time to run it, before it fails whole test
  for i in `seq 1 3`; do
    error=false

    oc process -n $namespace -o json $template_name NAME=$vm_name SRC_PVC_NAME=$TARGET-datavolume-original SRC_PVC_NAMESPACE=kubevirt | \
    jq 'del(.items[0].spec.dataVolumeTemplates[0].spec.pvc.accessModes) |
    .items[0].spec.dataVolumeTemplates[0].spec.pvc+= {"accessModes": ["ReadWriteOnce"]} | 
    .items[0].metadata.labels["vm.kubevirt.io/template.namespace"]="kubevirt"' | \
    oc apply -f -
    
    # start vm
    ./virtctl start $vm_name -n $namespace

    current_time=0
    while [ $(oc get pods -n $namespace | grep "cdi-upload-$vm_name.*Running" | wc -l ) -eq 0 ] ; do 
      oc get pods -n $namespace
      current_time=$((current_time + sample))
      if [ $current_time -gt $timeout ]; then
        error=true
        break
      fi
      sleep $sample;
    done

    # wait until import is finished
    current_time=0
    while [ $(oc get pods -n $namespace | grep "cdi-upload-$vm_name.*Running" | wc -l ) -gt 0 ] ; do 
      oc get pods -n $namespace
      current_time=$((current_time + sample))
      if [ $current_time -gt $timeout ]; then
        error=true
        break
      fi
      sleep $sample;
    done

    set +e
    current_time=0
    while [ $(oc get pods -n $namespace | grep "virt-launcher-$vm_name.*Running" | wc -l ) -eq 0 ] ; do 
      oc get pods -n $namespace
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

    # get ip address of vm
    ipAddressVMI=$(oc get vmi $vm_name -o json -n $namespace| jq -r '.status.interfaces[0].ipAddress')

    set +e
    pod_name=$(oc get pods -n $namespace | egrep -i '*virt-launcher*' | cut -d " " -f1)
    current_time=0
    # run ipconfig /all command on windows vm
    while [[ $(oc exec -n $namespace -it winrmcli -- ./usr/bin/winrm-cli -hostname $ipAddressVMI -port 5985 -username "Administrator" -password "Heslo123" "ipconfig /all" | grep "IPv4 Address" | wc -l ) -eq 0 ]] ; do 
      current_time=$((current_time + sample))
      if [[ $current_time -gt $timeout ]]; then
        error=true
        break
      fi
      sleep $sample;
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
