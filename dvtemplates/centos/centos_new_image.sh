#!/bin/bash

error_message() {
    if [ $1 -eq 1 ]; then
        echo -e "Unable to access data from the CentOS release URL"
    elif [ $1 -eq 2 ]; then
        echo -e "Invalid Image Version"
    elif [ $1 -eq 3 ]; then
        echo -e "Unable to connect to the CentOS Image repository"
    elif [ $1 -eq 4 ]; then
        echo -e "Container Image for the Latest CentOS version is already present. Exiting"
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

#Insecure registry port
port=5000

#set the final registry to hold the fedora images
CentOS_REPO="quay.io/shwetaap/centos-images"
BASE_URL=https://cloud.centos.org/centos/
#RELEASE_URL=https://getfedora.org/releases.json

wget -qO index.html $BASE_URL || exit 1
CentOS_VERSION=`cat index.html | sed -e 's/.*>\([0-9]\+\)\/<.*/\1/' | sort -rn | head -n 1 | tr -d ' '`
#CentOS_VERSION=`curl $RELEASE_URL | jq '.[] | select(.version|test("^[0-9]+$")) | .version' | sort -rn | uniq | head -n 1 | tr -d '"'`
re='^[0-9]+$'
if ! [[ $CentOS_VERSION =~ $re ]] ; then
    error_message 2
fi
echo "Latest CentOS version is : ${CentOS_VERSION}"

# Fetch the old image
docker pull -a $CentOS_REPO

#image_tag=$(docker images $CentOS_REPO --format "{{json .Tag }}" | sort -rn | head -n 1)
CentOS_OLD_VERSION=$(docker images $CentOS_REPO --format "{{json .}}" | jq 'select(.Tag|test("^[0-9]+$")) | .Tag' | sort -rn | head -n 1 | tr -d '"')
#CentOS_OLD_VERSION=`echo "$image_tag" | tr -d '"'`

echo "CentOS version in the Image Registry is : ${CentOS_OLD_VERSION}"

if [ -z "${CentOS_OLD_VERSION}" ]; then
    echo -e "No Container Image found in the registry"
fi


if [[ "$CentOS_VERSION" == "$CentOS_OLD_VERSION" ]]; then
    error_message 4
fi

IMAGE_URL=${BASE_URL}${CentOS_VERSION}/x86_64/images/
#URL=`curl $RELEASE_URL | jq '.[] | select(.link|test(".*qcow2")) | select(.version=='\"$CentOS_VERSION\"' and .variant=="Cloud" and .arch=="x86_64") | .link'`
wget -qO image.html $IMAGE_URL/CHECKSUM || exit 3
CentOS_IMAGE=$(grep ^#.*GenericCloud.*qcow2 image.html | sed -e 's/.*\(CentOS.*qcow2\).*/\1/')

URL=${IMAGE_URL}${CentOS_IMAGE}
echo "Image url : $URl"

wget -q --show-progress $URL || exit 3
echo -e "Successfully downloaded new  $CentOS_VERSION image"

docker build . -t localhost:${port}/disk
docker push localhost:${port}/disk || exit 5

# Run tests
cd ${PWD}/../;
curl https://mirror.openshift.com/pub/openshift-v4/clients/oc/4.4/linux/oc.tar.gz | tar -C . -xzf -
chmod +x oc
mv oc /usr/bin
export TARGET=refresh-image-centos${CentOS_VERSION}-test && export CLUSTERENV=K8s
./automation/test.sh || exit 7
#
# If testing passes push the new image to the final Image registry
docker tag localhost:${port}/disk $CentOS_REPO:$CentOS_VERSION
docker push $CentOS_REPO:$CentOS_VERSION || exit 6
