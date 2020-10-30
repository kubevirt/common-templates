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
# Copyright 2019 Red Hat, Inc.
#
set -ex

templates=("dist/templates/*.yaml")
for template in $templates; do

	os_name_prefix="^[[:space:]]*os.template.kubevirt.io/"
	template_oss=$(grep "$os_name_prefix" $template | cut -f1 -d":")

	workload_prefix="workload.template.kubevirt.io/"
	template_workloads=$(grep "$workload_prefix" $template | cut -f1 -d":")

	flavor_prefix="flavor.template.kubevirt.io/"
	template_flavors=$(grep "$flavor_prefix" $template | cut -f1 -d":")

	for os in $template_oss; do
		for workload in $template_workloads; do
			for flavor in $template_flavors; do
				count=$(oc get template -n kubevirt -l $os,$workload,$flavor --no-headers | wc -l)
				if [[ $count -ne 1 ]]; then
					echo "There are $count templates found with the following labels $os,$workload,$flavor"
					exit 1
				fi
			done
		done
	done
done
