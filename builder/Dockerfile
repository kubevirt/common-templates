# This Dockerfile is used in openshift CI
FROM quay.io/fedora/fedora:latest

# Install dependencies and tools
RUN dnf install -y jq ansible python3-gobject python3-openshift libosinfo make git findutils expect golang

# Allow writes to /etc/passwd so a user for ansible can be added by CI commands
RUN chmod a+w /etc/passwd

# Create ansible tmp folder and set permissions
RUN mkdir -p /.ansible/tmp && \
    chmod -R 777 /.ansible

# Download oc client binary
RUN curl https://mirror.openshift.com/pub/openshift-v4/x86_64/clients/oc/latest/linux/oc.tar.gz | tar -C /usr/local/bin -xzf - oc && \
    chmod +x /usr/local/bin/oc

# Download yq binary
RUN curl https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64 -o /usr/local/bin/yq && \
    chmod +x /usr/local/bin/yq
