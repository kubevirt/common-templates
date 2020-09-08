#!/bin/bash

set -ex

template_name=$1

timeout=600
sample=10

sizes=("tiny" "small" "medium" "large")
workloads=("desktop" "server" "highperformance")

if [[ $TARGET =~ rhel6.* ]]; then
  workloads=("desktop" "server")
fi

delete_vm(){
  vm_name=$1
  local template_name=$2
  set +e
  #stop vm
  ./virtctl stop $vm_name
  #delete vm
  oc process -o json $template_name NAME=$vm_name PVCNAME=$template_name | \
    oc delete -f -
  set -e
}

run_vm(){
  vm_name=$1
  template_path="dist/templates/$vm_name.yaml"
  local template_name=$( oc get -f ${template_path} -o=custom-columns=NAME:.metadata.name --no-headers -n kubevirt )
  running=false

  #If first try fails, it tries 2 more time to run it, before it fails whole test
  for i in `seq 1 3`; do
    error=false
    oc process -o json $template_name NAME=$vm_name PVCNAME=$TARGET | \
    jq '.items[0].metadata.labels["vm.kubevirt.io/template.namespace"]="kubevirt"' | \
    oc apply -f -

    #validator_pods=($(oc get pods -n kubevirt -l kubevirt.io=virt-template-validator -ocustom-columns=name:metadata.name --no-headers))

    #for pod in ${validator_pods[@]}; do
	    #oc logs -n kubevirt $pod
	  #done

    # start vm
    ./virtctl start $vm_name

    sleep 10

    set +e
    current_time=0
    while [ $(oc get vmi $vm_name -n kubevirt -o json | jq -r '.status.phase') != Running ] ; do 
      oc describe vmi $vm_name
      current_time=$((current_time + sample))
      if [ $current_time -gt $timeout ]; then
        error=true
        break
      fi
      oc describe -n kubevirt pv $TARGET
      oc describe -n kubevirt pvc $TARGET
      sleep $sample;
    done
    set -e

    if $error ; then
      #delete vm
      delete_vm $vm_name $template_name
      #jump to next iteration and try to run vm again
      continue
    fi

    oc describe vm $vm_name -n kubevirt
    oc describe vmi $vm_name -n kubevirt

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
