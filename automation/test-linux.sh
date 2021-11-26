#!/bin/bash

set -ex

template_name=$1
namespace="kubevirt"
ocenv="OC"
k8senv="K8s"

image_url=""
#set secret_ref only for rhel OSes
secret_ref=""
if [[ $TARGET =~ rhel.* ]]; then
  image_url="docker://quay.io/openshift-cnv/ci-common-templates-images:${TARGET}"
  secret_ref="secretRef: common-templates-container-disk-puller"
elif [[ $TARGET =~ refresh-image.* ]]; then
  if [[ $TARGET =~ refresh-image-fedora.* ]]; then
    template_name=fedora
  elif [[ $TARGET =~ refresh-image-centos.* ]]; then
    template_name=$(echo $TARGET | sed -e 's/.*\(centos[6-9]\)-test/\1/')
  fi
  # Local Insecure registry created by kubevirtci
  image_url="docker://registry:5000/disk"
  # Inform CDI the local registry is insecure
  oc patch configmap cdi-insecure-registries -n cdi --type merge -p '{"data":{"mykey": "registry:5000"}}'
  oc patch storageProfile local --type merge -p '{"spec": {"claimPropertySets":[{"accessModes": ["ReadWriteOnce"], "volumeMode": "Filesystem"}]}}'
else
  image_url="docker://quay.io/kubevirt/common-templates:${TARGET}"
fi

dv_name="${TARGET}-datavolume-original"

oc apply -n $namespace -f - <<EOF
apiVersion: cdi.kubevirt.io/v1beta1
kind: DataVolume
metadata:
  name: ${dv_name}
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

oc wait --for=condition=Ready --timeout=${timeout}s dv/${dv_name} -n $namespace

oc apply -n $namespace -f - <<EOF
apiVersion: cdi.kubevirt.io/v1beta1
kind: DataSource
metadata:
  name: ${dv_name}
spec:
  source:
    pvc:
      name: ${dv_name}
      namespace: ${namespace}
EOF

apply_only=false
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
if [[ $TARGET =~ .*saphana.* ]]; then
  workloads=("saphana")
  sizes=("tiny")
  apply_only=true
fi

delete_vm() {
  vm_name=$1

  local template_option=$2

  set +e
  #stop vm
  ./virtctl stop $vm_name -n $namespace
  #delete vm
  oc delete vm $vm_name -n $namespace
  set -e
  #wait until vm is deleted
  while oc get -n $namespace vmi $vm_name 2> >(grep "not found"); do sleep $sample; done
}

only_apply_vm() {
  vm_name=$1
  template_path="dist/templates/$vm_name.yaml"
  local template_option
  running=false

  set +e

  if [ "${CLUSTERENV}" == "$ocenv" ]; then
    local template_name=$(oc get -n ${namespace} -f ${template_path} -o=custom-columns=NAME:.metadata.name --no-headers -n kubevirt)
    template_option=${template_name}
  elif [ "${CLUSTERENV}" == "$k8senv" ]; then
    template_option="-f ${template_path} --local"
  fi

  error=false
  oc process ${template_option} -n $namespace -o json NAME=$vm_name SRC_PVC_NAME=$TARGET-datavolume-original SRC_PVC_NAMESPACE=kubevirt |
    jq '.items[0].metadata.labels["vm.kubevirt.io/template.namespace"]="kubevirt"' |
    oc apply -n $namespace -f -
}

run_vm() {
  vm_name=$1
  template_path="dist/templates/$vm_name.yaml"
  local template_option
  running=false

  set +e

  if [ "${CLUSTERENV}" == "$ocenv" ]; then
    local template_name=$(oc get -n ${namespace} -f ${template_path} -o=custom-columns=NAME:.metadata.name --no-headers -n kubevirt)
    template_option=${template_name}
  elif [ "${CLUSTERENV}" == "$k8senv" ]; then
    template_option="-f ${template_path} --local"
  fi

  #If first try fails, it tries 2 more time to run it, before it fails whole test
  for i in $(seq 1 3); do
    error=false
    oc process ${template_option} -n $namespace -o json NAME=$vm_name DATA_SOURCE_NAME=${dv_name} DATA_SOURCE_NAMESPACE=${namespace} |
      jq '.items[0].metadata.labels["vm.kubevirt.io/template.namespace"]="kubevirt"' |
      oc apply -n $namespace -f -

    ./virtctl version
    oc get vm $vm_name -n $namespace -oyaml
    # start vm
    ./virtctl start $vm_name -n $namespace

    oc wait --for=condition=Ready --timeout=${timeout}s vm/$vm_name -n $namespace

    ./automation/connect_to_rhel_console.exp $vm_name
    if [ $? -ne 0 ]; then
      error=true
    fi

    delete_vm $vm_name $template_option
    #no error were observed, the vm is running
    if ! $error; then
      running=true
      break
    fi
  done

  set -e

  if ! $running; then
    exit 1
  fi
}

for size in ${sizes[@]}; do
  for workload in ${workloads[@]}; do
    vm_name=$template_name-$workload-$size
    if [[ "${apply_only}" == "true" ]]; then
      only_apply_vm $vm_name
    else
      run_vm $vm_name
    fi
  done
done
