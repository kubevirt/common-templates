#!/bin/bash

error_message() {
    OS=$2
    if [ $1 -eq 1 ]; then
        echo -e "Unable to access data from the OS release URL"
    elif [ $1 -eq 2 ]; then
        echo -e "Invalid Image Version"
    elif [ $1 -eq 3 ]; then
        echo -e "Unable to connect to the OS Image repository"
    elif [ $1 -eq 4 ]; then
        echo -e "Container Image for the Latest $OS version is already present. Exiting"
    elif [ $1 -eq 5 ]; then
        echo -e "Unable to push the image to the local Registry."
    elif [ $1 -eq 6 ]; then
        echo -e "Unable to push the image to the Quay Registry."
    elif [ $1 -eq 7 ]; then
        echo -e "End to End Tests fail."
    elif [ $1 -eq 8 ]; then
        echo -e "No OS Image is set. Exiting!"
    fi
    exit $1
}

trap 'error_message $?' EXIT

#Insecure registry port
port=5000

# Check if OS_IMAGE is set
if [ -z "$OS_IMAGE" ]; then
    error_message 8
fi

FEDORA_OS="fedora"
CENTOS="centos"

#set the final registry to hold the contianer disk images
if [[ "${OS_IMAGE}" == "${CENTOS}" ]]; then
    cd ${PWD}/centos
    OS_REPO="quay.io/shwetaap/centos-images"
    BASE_URL=https://cloud.centos.org/centos/
    wget -qO index.html $BASE_URL || exit 1
    OS_VERSION=`cat index.html | sed -e 's/.*>\([0-9]\+\)\/<.*/\1/' | sort -rn | head -n 1 | tr -d ' '`
    # Use the following once we start building centos*-stream templates
    #cat index.html | sed -e 's/.*>\([0-9]\+\-stream\)\/<.*/\1/' | sort -rn
    #CentOS_VERSION=`curl $RELEASE_URL | jq '.[] | select(.version|test("^[0-9]+$")) | .version' | sort -rn | uniq | head -n 1 | tr -d '"'`
elif [[ "${OS_IMAGE}" == "${FEDORA_OS}" ]]; then
    cd ${PWD}/fedora
    OS_REPO="quay.io/kubevirt/fedora-images"
    RELEASE_URL=https://getfedora.org/releases.json
    wget -qO release.html $RELEASE_URL || exit 1
    OS_VERSION=`cat release.html | jq '.[] | select(.version|test("^[0-9]+$")) | .version' | sort -rn | uniq | head -n 1 | tr -d '"'`
fi
re='^[0-9]+$'
if ! [[ $OS_VERSION =~ $re ]] ; then
    error_message 2
fi
echo "Latest ${OS_IMAGE} version is : ${OS_VERSION}"

# Fetch the old image
docker pull -a $OS_REPO

#image_tag=$(docker images $CentOS_REPO --format "{{json .Tag }}" | sort -rn | head -n 1)
OS_OLD_VERSION=$(docker images $OS_REPO --format "{{json .}}" | jq 'select(.Tag|test("^[0-9]+$")) | .Tag' | sort -rn | head -n 1 | tr -d '"')
#CentOS_OLD_VERSION=`echo "$image_tag" | tr -d '"'`

echo "${OS_IMAGE} version in the Image Registry is : ${OS_OLD_VERSION}"

if [ -z "${OS_OLD_VERSION}" ]; then
    echo -e "No Container Image found in the registry"
fi


if [[ "$OS_VERSION" == "$OS_OLD_VERSION" ]]; then
    error_message 4 "$OS_IMAGE"
fi

if [[ "${OS_IMAGE}" == "${CENTOS}" ]]; then
    IMAGE_URL=${BASE_URL}${OS_VERSION}/x86_64/images/
    wget -qO image.html $IMAGE_URL/CHECKSUM || exit 3
    CentOS_IMAGE=$(grep ^#.*GenericCloud.*qcow2 image.html | sed -e 's/.*\(CentOS.*qcow2\).*/\1/')

    URL=${IMAGE_URL}${CentOS_IMAGE}
    echo "Image url : $URl"
elif [[ "${OS_IMAGE}" == "${FEDORA_OS}" ]]; then
    URL=`cat release.html | jq '.[] | select(.link|test(".*qcow2")) | select(.version=='\"$FEDORA_VERSION\"' and .variant=="Cloud" and .arch=="x86_64") | .link'`
fi

wget -q --show-progress $URL || exit 3
echo -e "Successfully downloaded new ${OS_IMAGE} version: ${OS_VERSION} image"

docker build . -t localhost:${port}/disk
docker push localhost:${port}/disk || exit 5

# Run tests
cd ${PWD}/../../;
curl https://mirror.openshift.com/pub/openshift-v4/clients/oc/4.4/linux/oc.tar.gz | tar -C . -xzf -
chmod +x oc
mv oc /usr/bin
export TARGET=refresh-image-${OS_IMAGE}${OS_VERSION}-test && export CLUSTERENV=K8s
./automation/test.sh || exit 7
#
# If testing passes push the new image to the final Image registry
docker tag localhost:${port}/disk $OS_REPO:$OS_VERSION
docker push $OS_REPO:$OS_VERSION || exit 6
