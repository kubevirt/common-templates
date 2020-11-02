#!/bin/bash
set -ex
make generate

#syntax check
templates=( dist/templates/* )
namespace="kubevirt"

oc apply -f - <<EOF
apiVersion: v1
kind: Namespace
metadata:
  name: ${namespace}
EOF

oc project $namespace

for template in $templates; do
    oc process -f "$template" NAME=test SRC_PVC_NAME=test || exit 1;
done

echo "Testing fresh installation..."
oc create -f dist/templates

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

echo "Testing upgrade..."
oc delete -f dist/templates

LATEST_CT=$(curl -L https://api.github.com/repos/kubevirt/common-templates/releases | \
            jq '.[] | select(.prerelease==false) | .name' | sort -V | tail -n1 | tr -d '"')
oc apply -f https://github.com/kubevirt/common-templates/releases/download/${LATEST_CT}/common-templates-${LATEST_CT}.yaml

oc apply -f dist/templates

./automation/test_duplicate_templates.sh
if [ $? -eq 1 ];then
  echo "[Upgrade] Validation of duplicate templates failed "
  exit 1
fi

./automation/test_defaults.sh 
if [ $? -eq 1 ];then
  echo "[Upgrade] Validation of default label failed "
  exit 1
fi
