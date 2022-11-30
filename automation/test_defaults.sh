#!/bin/bash
#
# This file is part of the KubeVirt project
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#
# Copyright 2020 Red Hat, Inc.
#
set -ex

# Any template can be used here as they all have the same version label, fedora is an arbitrary one
ver_label=$( \
  yq -o props '.metadata.labels | with_entries(select(.key == "template.kubevirt.io/version"))' \
  dist/templates/fedora-server-large.yaml \
)

readarray -t oss < <( \
  oc get templates -o yaml | \
  yq -o props '.items[].metadata.labels | . as $item ireduce ({}; . * $item) | with_entries(select(.key == "os.template.kubevirt.io/*"))' \
)

# Create an associative array containing all the possible labels
dist_templates=(dist/templates/*.yaml)
declare -A dist_templates_labels
for template in "${dist_templates[@]}"; do
  while read -r label; do
    dist_templates_labels[${label}]=""
  done < <( \
      yq -o props '.metadata.labels | with_entries(select(.key == "os.template.kubevirt.io/*"))' "$template" \
  )
done

# Ensure exactly one default variant per OS
for os in "${oss[@]}"; do
  if [[ ! -v dist_templates_labels[$os] ]]; then
    continue
  fi

  defaults=$(oc get template -l "$os,template.kubevirt.io/default-os-variant = true,$ver_label" -o name | wc -l)

  if [[ $defaults -eq 1 ]]; then
    continue
  elif [[ $defaults -eq 0 ]]; then
    echo "Error: No default variant set for $os"
    exit 1
  else
    echo "Error: There can only be 1 default variant per OS. $os has $defaults"
    exit 1
  fi
done
