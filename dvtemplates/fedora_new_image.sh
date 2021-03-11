#!/bin/bash

error_message() {
    if [ $1 -eq 1 ]; then
        echo -e "Unable to connect to the Fedora repository"
    elif [ $1 -eq 2 ]; then
        echo -e "Invalid Image Version"
    elif [ $1 -eq 3 ]; then
        echo -e "No Container Image found in the registry"
    elif [ $1 -eq 4 ]; then
        echo -e "Container Image for the Latest Fedora version is already present"
    fi
    exit
}

trap 'error_message $?' EXIT

#TODO : change it to https://quay.io/containerdisks/fedora_images ?
#FEDORA_REPO="quay.io/shwetaap/fedora_images"
#FEDORA_REPO=$1
#BASE_URL=https://download.fedoraproject.org/pub/fedora/linux/releases/

#wget -qO index.html $BASE_URL || exit 1
#FEDORA_VERSION=`cat index.html | sed -e 's/.*>\(.*\)\/<.*/\1/' | sort -rn | head -n 1`
#version_len=`echo ${FEDORA_VERESION} | wc -w`
#if [ $version_len -gt 1 ]; then
#    error_message 2
#fi

echo "Latest Fedora version is : ${FEDORA_VERSION}"

# Fetch the old image
docker pull -a $FEDORA_REPO || exit 3

image_tag=$(docker images $FEDORA_REPO --format "{{json .Tag }}" | sort -rn | head -n 1)
FEDORA_OLD_VERSION=`echo "$image_tag" | tr -d '"'`
echo "Fedora version in the Image Registry is : ${FEDORA_OLD_VERSION}"

if [ -z "$image_tag" ]; then


    #error_message 3
    echo -e "No Container Image found in the registry"
fi

# ToDo If we need to check the qcow disk image frp, within the container Disk Image
#image_id=$(docker images quay.io/shwetaap/containerdisk --format "{{json .ID }}")
#if [ -z "$image_id" ]; then

# Need to use a different base image as a scratch image will not run
#docker run $image_id
#docker ps -a
#docker cp 4824401d5785:/disk/ ./images/

if [ $FEDORA_VERSION == $FEDORA_OLD_VERSION ]; then
    error_message 4
fi

IMAGE_URL=${BASE_URL}${FEDORA_VERSION}/Cloud/x86_64/images/
wget -qO image.html $IMAGE_URL || exit 1
FEDORA_IMAGE=$(grep Fedora.*qcow2 image.html | sed -e 's/.*>\(Fedora.*qcow2\)<.*/\1/')

URL=${IMAGE_URL}${FEDORA_IMAGE}

wget -q --show-progress $URL || exit 1
echo -e "Successfully downloaded new Fedora $FEDORA_VERSION image"
