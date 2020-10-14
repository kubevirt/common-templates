#!/bin/bash

set -ex

template_name=$1
namespace="kubevirt"

image_url=""
if [[ $TARGET =~ rhel.* ]]; then
  image_url="docker://quay.io/openshift-cnv/ci-common-templates-images:${TARGET}"
else
  image_url="docker://quay.io/kubevirt/common-templates:${TARGET}"
fi;

oc apply -n $namespace -f - <<EOF
apiVersion: cdi.kubevirt.io/v1beta1
kind: DataVolume
metadata:
  name: ${TARGET}-datavolume-original
spec:
  source:
    registry:
      url: "${image_url}"
  pvc:
    accessModes:
      - ReadWriteOnce
    resources:
      requests:
        storage: 15Gi
EOF

timeout=600
sample=2
current_time=0
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

sizes=("tiny" "small" "medium" "large")
workloads=("desktop" "server" "highperformance")

if [[ $TARGET =~ rhel6.* ]]; then
  workloads=("desktop" "server")
fi

if [[ $TARGET =~ centos6.* ]]; then
  workloads=("server")
fi

if [[ $TARGET =~ ubuntu.* ]]; then
  workloads=("desktop")
fi

if [[ $TARGET =~ opensuse.* ]]; then
  workloads=("server")
fi

if [[ $TARGET =~ centos7.* ]] || [[ $TARGET =~ centos8.* ]]; then
  workloads=("server" "desktop")
fi

delete_vm(){
  vm_name=$1
  local template_name=$2
  set +e
  #stop vm
  ./virtctl stop $vm_name -n $namespace
  #delete vm
  oc process -n $namespace -o json $template_name NAME=$vm_name SRC_PVC_NAME=$TARGET-datavolume-original SRC_PVC_NAMESPACE=kubevirt | \
    oc delete -n $namespace -f -
  set -e
  #wait until vm is deleted
  while oc get -n $namespace vmi $vm_name 2> >(grep "not found") ; do sleep $sample; done
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
    oc apply -n $namespace -f -

    # start vm
    ./virtctl start $vm_name -n $namespace
    # wait until import pod is running
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

    if $error ; then
      #delete vm
      delete_vm $vm_name $template_name
      #jump to next iteration and try to run vm again
      continue
    fi

    set +e
    ./automation/connect_to_rhel_console.exp $vm_name
    if [ $? -ne 0 ] ; then 
      error=true
    fi
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
