# This Dockerfile is used in openshift CI
FROM quay.io/fedora/fedora:latest

# Install dependencies and tools
RUN dnf install -y jq ansible python3-gobject python3-openshift libosinfo intltool make git findutils expect golang

# Allow writes to /etc/passwd so a user for ansible can be added by CI commands
RUN chmod a+w /etc/passwd

# Create ansible tmp folder and set permissions
RUN mkdir -p /.ansible/tmp && \
    chmod -R 777 /.ansible

# Download latest stable oc client binary
RUN curl -L https://mirror.openshift.com/pub/openshift-v4/x86_64/clients/ocp/stable/openshift-client-linux.tar.gz | tar -C /usr/local/bin -xzf - oc && \
    chmod +x /usr/local/bin/oc

# Download latest yq binary
RUN curl -L https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64 -o /usr/local/bin/yq && \
    chmod +x /usr/local/bin/yq
