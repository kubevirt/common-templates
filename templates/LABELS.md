# Available labels

This file exemplarily describes the labels we will be using to select
the workload a template is supposed to be used for.

## Deprecated templates

When a template is deprecated, the following annotation is applied to it: `template.kubevirt.io/deprecated: "true"`.

The template itself is not removed for backward compatibility reasons.

## Operating systems

The operating system labels must match the [libosinfo
identifiers](https://gitlab.com/libosinfo/osinfo-db/tree/master/data/os) from the relevant xml files (look for short-id).

### Ubuntu

- os.template.kubevirt.io/ubuntuXX.XX (e.g. ubuntu20.04)

### Fedora

- os.template.kubevirt.io/fedoraXX (e.g. fedora 35)

### CentOS

- os.template.kubevirt.io/centosX.X (e.g. centos7.0)
- os.template.kubevirt.io/centos-streamX (e.g. centos-stream9)

### Red Hat Enterprise Linux

- os.template.kubevirt.io/rhelX.X (e.g. rhel8.0)

### openSUSE

- os.template.kubevirt.io/opensuseX.X (e.g. opensuse15.3)

### Microsoft Windows

- os.template.kubevirt.io/win2kXX (e.g. win2k19)
- os.template.kubevirt.io/winXX (e.g. win10)

## Workload profiles

- workload.template.kubevirt.io/desktop
- workload.template.kubevirt.io/server
- workload.template.kubevirt.io/highperformance
- workload.template.kubevirt.io/saphana

## Flavors

- flavor.template.kubevirt.io/tiny
- flavor.template.kubevirt.io/small
- flavor.template.kubevirt.io/medium
- flavor.template.kubevirt.io/large
