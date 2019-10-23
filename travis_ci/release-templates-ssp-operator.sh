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
set -e

if [ -z "${TRAVIS_TAG}" ]; then
	echo "TRAVIS_TAG can't be empty" && exit 1
fi

if [ -z "${GITHUB_TOKEN}" ]; then
  echo "GITHUB_TOKEN can't be empty" && exit 1
fi

git clone ${SSP_REPO_URL}
cd ${SSP_REPO}

# Configure github repo
git config user.email ${GH_USER_EMAIL}
git config user.name ${GH_USER_NAME}

branch="update-common-templates-${TRAVIS_TAG}"
git checkout -b $branch
git reset origin/master --hard

# Copy latest templates to ssp repo
cp ../dist/common-templates-${TRAVIS_TAG}.yaml roles/KubevirtCommonTemplatesBundle/files

# Replace templates_version to latest release
sed -i '/^templates_version.*/c\templates_version: '${TRAVIS_TAG} _defaults.yml

# Add only updated files and nothing else
git add _defaults.yml roles/KubevirtCommonTemplatesBundle/files/common-templates-${TRAVIS_TAG}.yaml

message="updated common templates to version ${TRAVIS_TAG}"
git commit -m "$message"
git push origin $branch --force

sleep 5

payload=$(cat <<- EOF
{
  "title": "${message}",
  "body": "${message}",
  "head": "$branch",
  "base": "master"
}
EOF
)
curl -d "$payload" -H "Authorization: token ${GITHUB_TOKEN}" -H "Content-Type: application/json" -X POST https://api.github.com/repos/${SSP_OWNER}/${SSP_REPO}/pulls 1> /dev/null
