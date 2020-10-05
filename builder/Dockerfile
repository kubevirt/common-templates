FROM fedora:30

RUN dnf install -y jq ansible libosinfo python3-gobject libosinfo intltool make git findutils qemu expect
RUN chmod uga+w /etc/passwd
ENV DEFAULT_LOCAL_TMP=/tmp
