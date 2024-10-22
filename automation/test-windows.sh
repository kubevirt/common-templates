#!/bin/bash

set -ex

namespace="kubevirt"
template_name="windows2k22"
username="Administrator"

sizes=("medium" "large")
workloads=("server" "highperformance")

if [[ $TARGET =~ windows10.* ]]; then
  template_name="windows10"
  workloads=("desktop")
elif [[ $TARGET =~ windows11.* ]]; then
  template_name="windows11"
  workloads=("desktop")
elif [[ $TARGET =~ windows2016.* ]]; then
  template_name="windows2k16"
elif [[ $TARGET =~ windows2019.* ]]; then
  template_name="windows2k19"
elif [[ $TARGET =~ windows2022.* ]]; then
  template_name="windows2k22"
elif [[ $TARGET =~ windows2025.* ]]; then
  template_name="windows2k25"
fi

source_name="${TARGET}-original"
version=$(oc version -o json | jq -r '.openshiftVersion | split("\\."; null)[:2]|join(".")')

oc apply -n ${namespace} -f - <<EOF
apiVersion: image.openshift.io/v1
kind: ImageStream
metadata:
  name: ${source_name}
spec:
  lookupPolicy:
    local: false
  tags:
  - from:
      kind: DockerImage
      name: ibmc.artifactory.cnv-qe.rhood.us/docker/kubevirt-common-instancetypes/${template_name}-container-disk:${version}
    name: "${version}"
    referencePolicy:
      type: Source
---
apiVersion: cdi.kubevirt.io/v1beta1
kind: DataImportCron
metadata:
  annotations:
    "cdi.kubevirt.io/storage.bind.immediate.requested": "true"
  name: ${source_name}
spec:
  template:
    spec:
      source:
        registry:
          imageStream: ${source_name}
          pullMethod: node
      storage:
        resources:
          requests:
            storage: 25Gi
  schedule: "46 10/12 * * *"
  garbageCollect: Outdated
  importsToKeep: 2
  managedDataSource: ${source_name}
EOF

timeout=2000
hour_timeout=3600
sample=10
current_time=0

oc wait --for=condition=UpToDate --timeout="${hour_timeout}s" "dataImportCron/${source_name}" -n "${namespace}"

delete_vm(){
  vm_name=$1
  set +e
  #stop vm
  ./virtctl stop $vm_name -n $namespace
  #delete vm
  oc delete vm $vm_name -n $namespace
  set -e
}

run_vm(){
  vm_name=$1
  template_path="dist/templates/$vm_name.yaml"
  local template_name=$( oc get -n ${namespace} -f ${template_path} -o=custom-columns=NAME:.metadata.name --no-headers -n kubevirt )
  running=false

  set +e

  #If first try fails, it tries 2 more time to run it, before it fails whole test
  for i in `seq 1 3`; do
    error=false

    oc process -n $namespace -o json $template_name NAME=$vm_name DATA_SOURCE_NAME=${source_name} DATA_SOURCE_NAMESPACE=${namespace} | \
    jq '.items[0].metadata.labels["vm.kubevirt.io/template.namespace"]="kubevirt"' | \
    oc apply -n $namespace -f -
    
    # start vm
    ./virtctl start "${vm_name}" -n "${namespace}"

    oc wait --for=condition=Ready --timeout="${hour_timeout}s" "vm/${vm_name}" -n "${namespace}"
        
    current_time=0
    # run command via ssh
    while [[ $(sshpass -pAdministrator ssh -o ProxyCommand="./virtctl port-forward  \
      --stdio=true -n ${namespace} vm/${vm_name} 33333:22" \
      -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no \
      "${username}@127.0.0.1" -p 33333 "echo Hello" | grep -c "Hello" ) != 1 ]] ; do
      # VM can be stopped during test and recreated. That will change IP, so to be sure, get IP at every iteration
      current_time=$((current_time + sample))
      if [[ $current_time -gt $timeout ]]; then
        error=true
        break
      fi
      sleep $sample;
    done

    delete_vm $vm_name $template_name
    #no error were observed, the vm is running
    if ! $error ; then
      running=true
      break
    fi
  done

  set -e

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
