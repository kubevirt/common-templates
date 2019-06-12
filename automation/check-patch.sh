#!/bin/bash -xe

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    TARGET="$0"
    TARGET="${TARGET#./}"
    TARGET="${TARGET%.*}"
    TARGET="${TARGET#*.}"
    echo "TARGET=$TARGET"
    export TARGET

    echo "Run functional tests"
    exec automation/test.sh
fi