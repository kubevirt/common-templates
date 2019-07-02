#!/bin/bash
if [ -z "${VERSION}" ]; then
	VERSION=$( git describe --tags | cut -d\- -f1)
fi
echo ${VERSION} | sed s/^v//
