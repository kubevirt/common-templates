#!/bin/bash

PV_NAME=$1
PV_SIZE=$2
PV_PATH=$3

cat <<EOF
apiVersion: "v1"
kind: "PersistentVolume"
metadata:
  name: "$PV_NAME"
  namespace: "kubevirt"
  labels:
    kubevirt.io/os: "$PV_NAME"
spec:
  capacity:
    storage: "$PV_SIZE"
  accessModes:
    - "ReadWriteOnce"
  persistentVolumeReclaimPolicy: Delete
  hostPath:
    path: "$PV_PATH"
---
kind: PersistentVolumeClaim
apiVersion: v1
metadata:
  namespace: "kubevirt"
  name: "$PV_NAME"
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: "$PV_SIZE"
  selector:
    matchLabels:
      kubevirt.io/os: "$PV_NAME"
EOF
