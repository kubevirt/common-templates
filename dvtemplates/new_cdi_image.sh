#!/bin/bash

set -e

ERROR_BASE_URL_UNREACHABLE=1
ERROR_INVALID_IMAGE=2
ERROR_IMAGE_URL_UNREACHABLE=3
ERROR_IMAGE_EXISTS=4
ERROR_LOCAL_REGISTRY=5
ERROR_QUAY_REGISTRY=6
ERROR_TESTS_FAIL=7
ERROR_MISSING_OS_IMAGE=8

error_message() {
    EXIT_VAL=$1
    OS="$2"
    if [ $EXIT_VAL -eq $ERROR_BASE_URL_UNREACHABLE ]; then
        echo -e "Unable to access data from the OS release URL"
    elif [ $EXIT_VAL -eq $ERROR_INVALID_IMAGE ]; then
        echo -e "Invalid Image Version"
    elif [ $EXIT_VAL -eq $ERROR_IMAGE_URL_UNREACHABLE ]; then
        echo -e "Unable to connect to the OS Image repository"
    elif [ $EXIT_VAL -eq $ERROR_IMAGE_EXISTS ]; then
        echo -e "Container Image for the Latest $OS version is already present. Exiting"
	exit 0
    elif [ $EXIT_VAL -eq $ERROR_LOCAL_REGISTRY ]; then
        echo -e "Unable to push the image to the local Registry."
    elif [ $EXIT_VAL -eq $ERROR_QUAY_REGISTRY ]; then
        echo -e "Unable to push the image to the Quay Registry."
    elif [ $EXIT_VAL -eq $ERROR_TESTS_FAIL ]; then
        echo -e "End to End Tests fail."
    elif [ $EXIT_VAL -eq $ERROR_MISSING_OS_IMAGE ]; then
        echo -e "No OS Image is set. Exiting!"
    fi
    exit $EXIT_VAL
}

trap 'error_message $?' EXIT

#Insecure registry port
port=5000

# Check if TARGET_OS is set
if [ -z "$TARGET_OS" ]; then
    error_message "$ERROR_MISSING_OS_IMAGE"
fi

FEDORA_OS="fedora"
CENTOS="centos8"

# Set the Image registry and identify the latest version of the OS
if [[ "${TARGET_OS}" == "${CENTOS}" ]]; then
    cd "${PWD}/centos8"
    OS_REPO="quay.io/kubevirt/centos8-container-disk-images"
    BASE_URL=https://cloud.centos.org/centos/8/x86_64/images/
    #IMAGE_URL=${BASE_URL}${OS_VERSION}/x86_64/images/
    wget -qO index.html $BASE_URL || exit "$ERROR_URL_UNREACHABLE"
    #OS_VERSION=`cat index.html | sed -e 's/.*>\([0-9]\+\)\/<.*/\1/' | sort -rn | head -n 1 | tr -d ' '`
    OS_IMAGE=$(grep "GenericCloud.*qcow2" index.html | sed -e 's/.*>\(.*qcow2\)<.*/\1/' | sort -r | head -n 1)
    OS_VERSION=$(echo $OS_IMAGE | sed -e 's/.*GenericCloud-\(.*\)-.*/\1/')
    echo $OS_VERSION
    re='^[0-9]+.[0-9]+.[0-9]+$'
    # Use the following once we start building centos*-stream templates
    #cat index.html | sed -e 's/.*>\([0-9]\+\-stream\)\/<.*/\1/' | sort -rn
    #CentOS_VERSION=`curl $RELEASE_URL | jq '.[] | select(.version|test("^[0-9]+$")) | .version' | sort -rn | uniq | head -n 1 | tr -d '"'`
elif [[ "${TARGET_OS}" == "${FEDORA_OS}" ]]; then
    cd "${PWD}/fedora"
    OS_REPO="quay.io/kubevirt/fedora-images"
    RELEASE_URL=https://getfedora.org/releases.json
    wget -qO release.html $RELEASE_URL || exit "$ERROR_URL_UNREACHABLE"
    OS_VERSION=`cat release.html | jq '.[] | select(.version|test("^[0-9]+$")) | .version' | sort -rn | uniq | head -n 1 | tr -d '"'`
    re='^[0-9]+$'
fi

if ! [[ $OS_VERSION =~ $re ]] ; then
    error_message "$ERROR_INVALID_IMAGE"
fi
echo "Latest ${TARGET_OS} version is : ${OS_VERSION}"

# Fetch the old image
docker pull -a $OS_REPO

#image_tag=$(docker images $CentOS_REPO --format "{{json .Tag }}" | sort -rn | head -n 1)
OS_OLD_VERSION=$(docker images $OS_REPO --format "{{json .}}" | jq 'select(.Tag|test("^[0-9]+$")) | .Tag' | sort -rn | head -n 1 | tr -d '"')
#CentOS_OLD_VERSION=`echo "$image_tag" | tr -d '"'`

echo "${TARGET_OS} version in the Image Registry is : ${OS_OLD_VERSION}"

if [ -z "${OS_OLD_VERSION}" ]; then
    echo -e "No Container Image found in the registry"
fi

if [[ "$OS_VERSION" == "$OS_OLD_VERSION" ]]; then
    error_message "$ERROR_IMAGE_EXISTS" "$TARGET_OS"
fi

#Download the latest OS Image
if [[ "${TARGET_OS}" == "${CENTOS}" ]]; then
    #IMAGE_URL=${BASE_URL}${OS_VERSION}/x86_64/images/
    #wget -qO image.html $IMAGE_URL/CHECKSUM || exit 3
    #CentOS_IMAGE=$(grep ^#.*GenericCloud.*qcow2 image.html | sed -e 's/.*\(CentOS.*qcow2\).*/\1/')
    #wget -qO image.html $IMAGE_URL || exit 3
    #CentOS_IMAGE=$(grep GenericCloud.*qcow2 image.html | sed -e 's/.*>\(.*qcow2\)<.*/\1/' | sort -r | head -n 1)
    #CentOS_VERSION=$(echo $CentOS_IMAGE | sed -e 's/.*GenericCloud-\(.*\)-.*/\1/')
    URL="${BASE_URL}${OS_IMAGE}"
    echo "Image url : $URL"
    IMG_LABEL='io.kubevirt.image.source_code="https://vault.centos.org/'"${OS_VERSION}"'/"'
elif [[ "${TARGET_OS}" == "${FEDORA_OS}" ]]; then
    URL=`cat release.html | jq '.[] | select(.link|test(".*qcow2")) | select(.version=='\"$OS_VERSION\"' and .variant=="Cloud" and .arch=="x86_64") | .link' | tr -d '"'`
    echo "Image url : $URL"
    IMG_LABEL='io.kubevirt.image.source_code="https://download.fedoraproject.org/pub/fedora/linux/releases/'"${OS_VERSION}"'/Everything/source/tree"'
fi

wget -q --show-progress $URL || exit "$ERROR_IMAGE_URL_UNREACHABLE"
echo -e "Successfully downloaded new ${TARGET_OS} version: ${OS_VERSION} image"

# Build and push the qcow2 Image in a Container to a local registry for testing
docker build . --label $IMG_LABEL -t localhost:${port}/disk
docker push localhost:${port}/disk || exit "$ERROR_LOCAL_REGISTRY"

# Run tests
cd "${PWD}/../../"
curl https://mirror.openshift.com/pub/openshift-v4/clients/oc/4.4/linux/oc.tar.gz | tar -C . -xzf -
chmod +x oc
mv oc /usr/bin
export TARGET=refresh-image-${TARGET_OS}-test && export CLUSTERENV=K8s
./automation/test.sh || exit "$ERROR_TESTS_FAIL"
#
# If testing passes push the new image to the final Image registry
docker tag localhost:${port}/disk $OS_REPO:$OS_VERSION
docker push $OS_REPO:$OS_VERSION || exit "$ERROR_QUAY_REGISTRY"
