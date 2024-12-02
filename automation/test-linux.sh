#!/bin/bash

set -ex

template_name=$1
namespace="kubevirt"
ocenv="OC"
k8senv="K8s"

containerdisks_url="docker://quay.io/containerdisks"
legacy_common_templates_disk_url="docker://quay.io/kubevirt/common-templates"
cnv_common_templates_url="docker://quay.io/openshift-cnv/ci-common-templates-images"
image_url=""
#set secret_ref only for rhel OSes
secret_ref=""

case $TARGET in
  centos-stream9)
    image_url="${containerdisks_url}/centos-stream:9"
    ;;
  centos6)
    image_url="${legacy_common_templates_disk_url}:centos6"
    ;;
  fedora)
    image_url="${containerdisks_url}/fedora:latest"
    ;;
  opensuse)
    image_url="${containerdisks_url}/opensuse-leap:15.6"
    ;;
  rhel*)
    image_url="${cnv_common_templates_url}:${TARGET}"
    secret_ref="secretRef: common-templates-container-disk-puller"
    ;;
  ubuntu)
    image_url="${containerdisks_url}/ubuntu:24.04"
    ;;
  *)
    echo "Target: $TARGET is not valid"
    exit 1
    ;;
esac

dv_name="${TARGET}-datavolume-original"

oc apply -n $namespace -f - <<EOF
apiVersion: cdi.kubevirt.io/v1beta1
kind: DataVolume
metadata:
  annotations:
    cdi.kubevirt.io/storage.bind.immediate.requested: "true"
  name: ${dv_name}
spec:
  source:
    registry:
      url: "${image_url}"
      ${secret_ref}
  storage:
    accessModes:
      - ReadWriteOnce
    resources:
      requests:
        storage: 30Gi
EOF

timeout=900
sample=10

oc wait --for=condition=Ready --timeout=${timeout}s dv/"${dv_name}" -n $namespace

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

sizes=("tiny" "small" "medium" "large")
workloads=("desktop" "server")

if [[ $TARGET =~ fedora.* ]]; then
  sizes=("small" "medium" "large")
fi

if [[ $TARGET =~ centos6.* ]]; then
  workloads=("server")
fi

if [[ $TARGET =~ ubuntu.* ]]; then
  workloads=("desktop" "server")
  sizes=("small" "medium" "large")
fi

if [[ $TARGET =~ opensuse.* ]]; then
  workloads=("server")
fi

if [[ $TARGET =~ centos-stream.* ]]; then
  workloads=("server" "desktop")
fi

delete_vm() {
  vm_name=$1

  local template_option=$2

  set +e
  #stop vm
  ./virtctl stop "$vm_name" -n $namespace
  #delete vm
  oc delete vm "$vm_name" -n $namespace
  set -e
  #wait until vm is deleted
  while oc get -n $namespace vmi "$vm_name" 2> >(grep "not found"); do sleep $sample; done
}

run_vm() {
  vm_name=$1
  template_path="dist/templates/$vm_name.yaml"
  local template_option
  running=false

  set +e

  local template_name=$(oc get -n ${namespace} -f "${template_path}" -o=custom-columns=NAME:.metadata.name --no-headers -n kubevirt)
  template_option=${template_name}

  #If first try fails, it tries 2 more time to run it, before it fails whole test
  for i in $(seq 1 3); do
    error=false
    oc process "${template_option}" -n $namespace -o json NAME="$vm_name" DATA_SOURCE_NAME="${dv_name}" DATA_SOURCE_NAMESPACE=${namespace} |
      jq '.items[0].metadata.labels["vm.kubevirt.io/template.namespace"]="kubevirt"' |
      oc apply -n $namespace -f -

    ./virtctl version
    oc get vm "$vm_name" -n "$namespace" -oyaml
    # start vm
    ./virtctl start "$vm_name" -n "$namespace"

    oc wait --for=condition=Ready --timeout=${timeout}s vm/"$vm_name" -n $namespace

    ./automation/connect_to_rhel_console.exp "$vm_name"
    if [ $? -ne 0 ]; then
      error=true
    fi

    delete_vm "$vm_name" "$template_option"
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

target_arch_suffix=$( [ "$TARGET_ARCH" = "x86_64" ] && echo "" || echo "-$TARGET_ARCH" )
for size in "${sizes[@]}"; do
  for workload in "${workloads[@]}"; do
    vm_name=$template_name-$workload-$size$target_arch_suffix
    run_vm "$vm_name"
  done
done
