#!/bin/bash

set -ex

template_name=$1
namespace="kubevirt"
#template_local=""
#template_option=$template_name

image_url=""
#set secret_ref only for rhel OSes
secret_ref=""
if [[ $TARGET =~ rhel.* ]]; then
  image_url="docker://quay.io/openshift-cnv/ci-common-templates-images:${TARGET}"
  secret_ref="secretRef: common-templates-container-disk-puller"
elif [[ $TARGET =~ refresh-image-fedora-test.* ]]; then
  #dnscont=k8s-1.20-dnsmasq
  #port=$(docker port $dnscont 5000 | awk -F : '{ print $2 }')
  #echo $port
  template_name=fedora
  # Local Insecure registry created by kubevirtci
  image_url="docker://registry:5000/disk"
  # Inform CDI the local registry is insecure
  ${KUBE_CMD} patch configmap cdi-insecure-registries -n cdi --type merge -p '{"data":{"mykey": "registry:5000"}}'
  # TODO: Remove after this CDI bug is fixed - https://github.com/kubevirt/containerized-data-importer/issues/1656
  # contenttype="contentType: kubevirt"
else
  image_url="docker://quay.io/kubevirt/common-templates:${TARGET}"
fi;

${KUBE_CMD} apply -n $namespace -f - <<EOF
apiVersion: cdi.kubevirt.io/v1beta1
kind: DataVolume
metadata:
  name: ${TARGET}-datavolume-original
spec:
  source:
    registry:
      url: "${image_url}"
      ${secret_ref}
  pvc:
    accessModes:
      - ReadWriteOnce
    resources:
      requests:
        storage: 30Gi
EOF

timeout=600
sample=10

${KUBE_CMD} wait --for=condition=Ready --timeout=${timeout}s dv/${TARGET}-datavolume-original -n $namespace

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

#if [[ $TARGET =~ fedora ]]; then
#  workloads=("desktop" "server")
#fi

delete_vm(){
  vm_name=$1
  #local template_option

  #if [ "${KUBE_CMD}" == "oc" ]; then
  #    echo $KUBE_CMD
  #    template_option=$2
  #elif [ "${KUBE_CMD}" == "kubectl" ]; then
  #    echo $KUBE_CMD
  #    template_option="-f $2 --local"
#      template_local="--local"
  #fi

  set +e
  #stop vm
  ./virtctl stop $vm_name -n $namespace
  #delete vm
  oc process $2 -n $namespace -o json NAME=$vm_name SRC_PVC_NAME=$TARGET-datavolume-original SRC_PVC_NAMESPACE=kubevirt | \
    ${KUBE_CMD} delete -n $namespace -f -
  set -e
  #wait until vm is deleted
  while ${KUBE_CMD} get -n $namespace vmi $vm_name 2> >(grep "not found") ; do sleep $sample; done
}

run_vm(){
  vm_name=$1
  template_path="dist/templates/$vm_name.yaml"
  local template_option
  running=false

  # add cpumanager=true label to all worker nodes
  # to allow execution of tests using high performance profiles
  # ${KUBE_CMD} label nodes -l kubevirt.io/schedulable cpumanager=true --overwrite

  if [ "${KUBE_CMD}" == "oc" ]; then
      echo $KUBE_CMD
      local template_name=$( ${KUBE_CMD} get -n ${namespace} -f ${template_path} -o=custom-columns=NAME:.metadata.name --no-headers -n kubevirt )
      template_option=${template_name}
  elif [ "${KUBE_CMD}" == "kubectl" ]; then
      echo $KUBE_CMD
      template_option="-f ${template_path} --local"
      #template_local="--local"
  fi

  #If first try fails, it tries 2 more time to run it, before it fails whole test
  for i in `seq 1 3`; do
    error=false
    oc process ${template_option} -n $namespace -o json NAME=$vm_name SRC_PVC_NAME=$TARGET-datavolume-original SRC_PVC_NAMESPACE=kubevirt | \
    jq 'del(.items[0].spec.dataVolumeTemplates[0].spec.pvc.accessModes) |
    .items[0].spec.dataVolumeTemplates[0].spec.pvc+= {"accessModes": ["ReadWriteOnce"]} | 
    .items[0].metadata.labels["vm.kubevirt.io/template.namespace"]="kubevirt"' | \
    ${KUBE_CMD} apply -n $namespace -f -

    ./virtctl version
    ${KUBE_CMD} get vm $vm_name -n $namespace -oyaml
    # start vm
    ./virtctl start $vm_name -n $namespace

    ${KUBE_CMD} wait --for=condition=Ready --timeout=${timeout}s vm/$vm_name -n $namespace

    ./automation/connect_to_rhel_console.exp $vm_name
    if [ $? -ne 0 ] ; then 
      error=true
    fi
  
    delete_vm $vm_name $template_option
   # if [ "${KUBE_CMD}" == "oc" ]; then
     #   echo $KUBE_CMD
     #   delete_vm $vm_name $template_option
    #elif [ "${KUBE_CMD}" == "kubectl" ]; then
#	echo $KUBE_CMD
 #       delete_vm $vm_name $template_option
  #  fi
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
