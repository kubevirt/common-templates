FROM fedora:30

RUN dnf install -y jq ansible libosinfo python3-gobject libosinfo intltool make git findutils qemu expect
RUN chmod uga+w /etc/passwd

#set permissions for ansible tmp folder
RUN mkdir -p /.ansible/tmp
RUN chmod -R 777 /.ansible

# download oc client binary
RUN curl https://mirror.openshift.com/pub/openshift-v4/clients/oc/4.4/linux/oc.tar.gz | tar -C . -xzf -
RUN chmod +x oc
RUN mv oc /usr/bin
