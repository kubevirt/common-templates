#!/bin/bash

error_message() {
    if [ $1 -eq 1 ]; then
        echo -e "Unable to access data from the Fedora release URL"
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

#Insecure registry port
port=5000

#set the final registry to hold the fedora images
FEDORA_REPO="quay.io/kubevirt/fedora-images"
#BASE_URL=https://download.fedoraproject.org/pub/fedora/linux/releases/
RELEASE_URL=https://getfedora.org/releases.json

#wget -qO index.html $BASE_URL || exit 1
#FEDORA_VERSION=`cat index.html | sed -e 's/.*>\(.*\)\/<.*/\1/' | sort -rn | head -n 1 | tr -d ' '`
FEDORA_VERSION=`curl $RELEASE_URL | jq '.[] | select(.version|test("^[0-9]+$")) | .version' | sort -rn | uniq | head -n 1 | tr -d '"'`
re='^ *[0-9]+ *$'
if ! [[ $FEDORA_VERSION =~ $re ]] ; then
    error_message 2
fi
echo "Latest Fedora version is : ${FEDORA_VERSION}"

# Fetch the old image
docker pull -a $FEDORA_REPO

#image_tag=$(docker images $FEDORA_REPO --format "{{json .Tag }}" | sort -rn | head -n 1)
FEDORA_OLD_VERSION=$(docker images $FEDORA_REPO --format "{{json .}}" | jq 'select(.Tag|test("^[0-9]+$")) | .Tag' | sort -rn | head -n 1 | tr -d '"')
#FEDORA_OLD_VERSION=`echo "$image_tag" | tr -d '"'`

echo "Fedora version in the Image Registry is : ${FEDORA_OLD_VERSION}"

if [ -z "$image_tag" ]; then
    echo -e "No Container Image found in the registry"
fi

if [[ "$FEDORA_VERSION" == "$FEDORA_OLD_VERSION" ]]; then
    error_message 4
fi

#IMAGE_URL=${BASE_URL}${FEDORA_VERSION}/Cloud/x86_64/images/
URL=`curl $RELEASE_URL | jq '.[] | select(.link|test(".*qcow2")) | select(.version=='\"$FEDORA_VERSION\"' and .variant=="Cloud" and .arch=="x86_64") | .link'`
#wget -qO image.html $IMAGE_URL || exit 3
#FEDORA_IMAGE=$(grep Fedora.*qcow2 image.html | sed -e 's/.*>\(Fedora.*qcow2\)<.*/\1/')

#URL=${IMAGE_URL}${FEDORA_IMAGE}

wget -q --show-progress $URL || exit 3
echo -e "Successfully downloaded new Fedora $FEDORA_VERSION image"

docker build . -t localhost:${port}/disk
docker push localhost:${port}/disk || exit 5

# Run tests
cd ${PWD}/../;

curl https://mirror.openshift.com/pub/openshift-v4/clients/oc/4.4/linux/oc.tar.gz | tar -C . -xzf -
chmod +x oc
mv oc /usr/bin
export TARGET=refresh-image-fedora-test && export CLUSTERENV=K8s
./automation/test.sh || exit 7
#
# If testing passes push the new image to the final Image registry
docker tag localhost:${port}/disk $FEDORA_REPO:$FEDORA_VERSION
docker push $FEDORA_REPO:$FEDORA_VERSION || exit 6