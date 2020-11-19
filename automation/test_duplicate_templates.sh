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

ver_label='^[[:space:]]*template.kubevirt.io/version'
# Any template can be used here as they all have the same verison label, centos is an arbitrary one
ver_value=$(grep "$ver_label" dist/templates/centos6-server-large.yaml | tail -1 | cut -f2 -d":" | tr -d ' "')
ver_label="template.kubevirt.io/version=$ver_value"
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
				count=$(oc get template -l $os,$workload,$flavor,$ver_label --no-headers | wc -l)
				if [[ $count -ne 1 ]]; then
					echo "There are $count templates found with the following labels $os,$workload,$flavor,$ver_label"
					exit 1
				fi
			done
		done
	done
done
