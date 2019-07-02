#!/bin/bash
if [ -z "${REVISION}" ]; then
	REVISION=$( git describe --tags | cut -d\- -f2)
fi
echo ${REVISION} | sed s/^v//
