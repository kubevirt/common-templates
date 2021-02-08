#!/bin/bash

error_message() {
    if [ $1 -eq 1 ]; then
        echo -e "Unable to connect to the Fedora repository"
    elif [ $1 -eq 2 ]; then
        echo -e "Invalid Image Version"
    elif [ $1 -eq 3 ]; then
        echo -e "Unable to connect to the Fedora Image repository"
    elif [ $1 -eq 4 ]; then
        echo -e "Container Image for the Latest Fedora version is already present. Exiting"
    elif [ $1 -eq 5 ]; then
        echo -e "Unable to push the image to the local Registry."
    elif [ $1 -eq 6 ]; then
        echo -e "Unable to push the image to the Quay Registry."
    elif [ $1 -eq 7 ]; then
        echo -e "End to End Tests fail."
    fi
    exit $1
}

trap 'error_message $?' EXIT

host=$(hostname)
echo $host
dnscont=k8s-1.20-dnsmasq
port=$(docker port $dnscont 5000 | awk -F : '{ print $2 }')
echo $port
cat > /etc/docker/daemon.json << EOF
{
    "live-restore": true,
    "insecure-registries": ["$host:$port"]
}
EOF
service docker restart

#TODO : change it to https://quay.io/containerdisks/fedora_images ?
FEDORA_REPO="quay.io/shwetaap/fedora_images"
#FEDORA_REPO=$1
BASE_URL=https://download.fedoraproject.org/pub/fedora/linux/releases/

wget -qO index.html $BASE_URL || exit 1
FEDORA_VERSION=`cat index.html | sed -e 's/.*>\(.*\)\/<.*/\1/' | sort -rn | head -n 1`
#version_len=`echo ${FEDORA_VERESION} | wc -w`
#if [ $version_len -gt 1 ]; then
#    error_message 2
#fi
re='^ *[0-9]+ *$'
if ! [[ $FEDORA_VERSION =~ $re ]] ; then
    error_message 2
fi
echo "Latest Fedora version is : ${FEDORA_VERSION}"

# Fetch the old image
docker pull -a $FEDORA_REPO

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

if [[ "$FEDORA_VERSION" == "$FEDORA_OLD_VERSION" ]]; then
    error_message 4
fi

IMAGE_URL=${BASE_URL}${FEDORA_VERSION}/Cloud/x86_64/images/
wget -qO image.html $IMAGE_URL || exit 3
FEDORA_IMAGE=$(grep Fedora.*qcow2 image.html | sed -e 's/.*>\(Fedora.*qcow2\)<.*/\1/')

URL=${IMAGE_URL}${FEDORA_IMAGE}

wget -q --show-progress $URL || exit 3
echo -e "Successfully downloaded new Fedora $FEDORA_VERSION image"

docker build . -t ${host}:${port}/disk
docker push ${host}:${port}/disk || exit 5
       # if [ $? -ne 0 ]; then
       #     echo -e "Unable to push the image to the local registry"
       #     exit 1
       # fi

# Run tests
cd ${PWD}/../;
# Install expect to enable login to machines in the test scripts
# apt-get update && apt-get install -y expect
# pip3 install six
curl https://mirror.openshift.com/pub/openshift-v4/clients/oc/4.4/linux/oc.tar.gz | tar -C . -xzf -
chmod +x oc
mv oc /usr/bin
export TARGET=refresh-image-fedora-test && export KUBE_CMD=kubectl
./automation/test.sh || exit 7
#
# If testing passes push the new image to the final Image registry
cat $QUAY_PASSWORD | docker login --username $(cat $QUAY_USER) --password-stdin=true quay.io
docker tag ${host}:${port}/disk $FEDORA_REPO:$FEDORA_VERSION
docker push $FEDORA_REPO:$FEDORA_VERSION || exit 6
    #if [ $? -ne 0 ]; then
    #    echo -e "Unable to push the image to the quay registry"
    #    exit 1
    #fi
#else
#    echo -e "End to end tests fail using the fedora container disk image"
#    exit 1
#fi
