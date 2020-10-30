#!/bin/bash
set -ex
make generate

#syntax check
templates=($(grep -L "template.kubevirt.io/deprecated: \"true\"" dist/templates/*))
namespace="kubevirt"
oc create namespace $namespace

for template in $templates; do
    oc process -f "$template" -n $namespace NAME=test SRC_PVC_NAME=test || exit 1;
done

oc create -n $namespace -f dist/templates

#check validation part
python3 automation/check-validations.py
if [ $? -eq 1 ];then
  echo "Validation of validations failed"
  exit 1
fi

#check minimal memory again 
python3 automation/validate-min-memory-consistency.py
if [ $? -eq 1 ];then
  echo "Validation of memory requirements failed"
  exit 1
fi

./automation/test_duplicate_templates.sh
if [ $? -eq 1 ];then
  echo "Validation of duplicate templates failed "
  exit 1
fi

./automation/test_defaults.sh 
if [ $? -eq 1 ];then
  echo "Validation of default label failed "
  exit 1
fi
