#!/bin/bash

_oc() { 
  cluster/kubectl.sh "$@"
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
sleep 10
timeout=600
sample=10

kubeconfig="cluster/$KUBEVIRT_PROVIDER/.kubeconfig"

sizes=("tiny" "small" "medium" "large")
workloads=("desktop" "server" "highperformance")

if [[ $TARGET =~ rhel6.* ]]; then
  workloads=("desktop" "server")
fi

for size in ${sizes[@]}; do
  for workload in ${workloads[@]}; do
    templatePath="../../dist/templates/$template_name-$workload-$size.yaml"

    _oc process -o json --local -f $templatePath NAME="$template_name-$workload-$size" PVCNAME=disk-rhel | \
    jq '.items[0].spec.template.spec.volumes[0]+= {"ephemeral": {"persistentVolumeClaim": {"claimName": "disk-rhel"}}} | 
    del(.items[0].spec.template.spec.volumes[0].persistentVolumeClaim)' | \
    _oc apply -f -

    # start vm
    ./virtctl --kubeconfig=$kubeconfig start "$template_name-$workload-$size"

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

    current_time=0
    while [  $(./connect_to_rhel_console.exp $kubeconfig $template_name-$workload-$size | grep login | wc -l) -lt 1 ] ; do 
      echo "waiting for vm to be ready"

      current_time=$((current_time + sample))
      if [ $current_time -gt $timeout ]; then
        echo "It should show login prompt"
        exit 1
      fi
      sleep $sample;
    done

    ./virtctl --kubeconfig=$kubeconfig stop "$template_name-$workload-$size" 

    _oc process -o json --local -f $templatePath NAME=$template_name-$workload-$size PVCNAME=disk-rhel | \
    _oc delete -f -
    set -e
  done
done