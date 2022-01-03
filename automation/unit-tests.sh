#!/bin/bash
set -ex
make generate

#syntax check
templates=$(ls dist/templates/*)
namespace="kubevirt"

echo "Testing fresh installation..."
oc apply -f - <<EOF
apiVersion: v1
kind: Namespace
metadata:
  name: ${namespace}
EOF

oc project $namespace

echo "Printing templates to stdout for debugging"
for template in $templates; do
  cat "$template"
done

echo "Processing all templates to find syntax issues"
for template in $templates; do
  if [[ $template =~ .*saphana.* ]]; then
    oc process -f "$template" NAME=test WORKLOAD_NODE_LABEL_VALUE="somevalue" SRIOV_NETWORK_NAME1="default/sriov1"  SRIOV_NETWORK_NAME2="default/sriov1"  SRIOV_NETWORK_NAME3="default/sriov1"|| exit 1
  else
    oc process -f "$template" NAME=test DATA_SOURCE_NAME=test || exit 1
  fi
done

oc create -f dist/templates

#check validation part
python3 automation/check-validations.py
if [ $? -eq 1 ]; then
  echo "Validation of validations failed"
  exit 1
fi

#check minimal memory again
python3 automation/validate-min-memory-consistency.py
if [ $? -eq 1 ]; then
  echo "Validation of memory requirements failed"
  exit 1
fi

echo "Testing upgrade..."
oc delete -f dist/templates

LATEST_CT=$(curl -L https://api.github.com/repos/kubevirt/common-templates/releases |
  jq '.[] | select(.prerelease==false) | .name' | sort -V | tail -n1 | tr -d '"')
oc apply -f https://github.com/kubevirt/common-templates/releases/download/${LATEST_CT}/common-templates.yaml

set +e
python3 automation/validate-pvc-name-stability.py
RC=${?}
set -e
echo "[Upgrade][test_id:5749] Validation of PVC name stability"
if [ ${RC} -ne 0 ]; then
  echo "[Upgrade][test_id:5749] Validation of PVC name stability failed"
  exit ${RC}
fi

oc apply -f dist/templates

./automation/test_duplicate_templates.sh
if [ $? -eq 1 ]; then
  echo "[Upgrade] Validation of duplicate templates failed "
  exit 1
fi

./automation/test_defaults.sh
if [ $? -eq 1 ]; then
  echo "[Upgrade] Validation of default label failed "
  exit 1
fi
