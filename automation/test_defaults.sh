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

namespace="kubevirt"
templates_dir='dist/templates'
default_label='template.kubevirt.io/default-os-variant=true'
os_label='os.template.kubevirt.io/'
template='{{range .items}}{{range $key, $val := .metadata.labels}}{{if eq $val "true"}}{{$key}}{{"\n"}}{{end}}{{end}}{{end}}'

# Ensure exactly one default variant per OS
for os in $(oc get templates -n $namespace -o go-template="$template" | grep "^$os_label" | sort -uV); do
    defaults=$(oc get template -n $namespace -l ${os}=true,template.kubevirt.io/default-os-variant=true -o name | wc -l)
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
