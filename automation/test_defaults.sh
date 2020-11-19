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

templates_dir='dist/templates'
default_label='template.kubevirt.io/default-os-variant=true'
os_label='os.template.kubevirt.io/'
template='{{range .items}}{{range $key, $val := .metadata.labels}}{{if eq $val "true"}}{{$key}}{{"\n"}}{{end}}{{end}}{{end}}'
ver_label='^[[:space:]]*template.kubevirt.io/version'
# Any template can be used here as they all have the same verison label, centos is an arbitrary one
ver_value=$(grep "$ver_label" $templates_dir/centos6-server-large.yaml | tail -1 | cut -f2 -d":" | tr -d ' "')
ver_label="template.kubevirt.io/version=$ver_value"

# Ensure exactly one default variant per OS
for os in $(oc get templates -o go-template="$template" | grep "^$os_label" | sort -uV); do
    defaults=$(oc get template -l ${os}=true,template.kubevirt.io/default-os-variant=true,$ver_label -o name | wc -l)
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
