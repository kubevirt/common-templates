# Available labels

This file describes the labels we will be using to select
the workload a template is supposed to be used for.

Some of them are not going to be used immediately and serve
as examples.

## Operating systems

The operating system labels must match the [libosinfo
identifiers](https://gitlab.com/libosinfo/osinfo-db/tree/master/data/os) from the relevant xml files (look for short-id).

### Ubuntu

- os.template.kubevirt.io/ubuntu18.04
- os.template.kubevirt.io/ubuntu17.10
- os.template.kubevirt.io/ubuntu17.04
- os.template.kubevirt.io/ubuntu16.10
- os.template.kubevirt.io/ubuntu16.04

### Fedora

- os.template.kubevirt.io/fedora29
- os.template.kubevirt.io/fedora28
- os.template.kubevirt.io/fedora27
- os.template.kubevirt.io/fedora26
- os.template.kubevirt.io/fedora25
- os.template.kubevirt.io/fedora24
- os.template.kubevirt.io/fedora23

### CentOS

- os.template.kubevirt.io/centos7.0
- os.template.kubevirt.io/centos6.9
- os.template.kubevirt.io/centos6.8
- os.template.kubevirt.io/centos6.7

### Red Hat Enterprise Linux

- os.template.kubevirt.io/rhel7.0
- os.template.kubevirt.io/rhel7.1
- os.template.kubevirt.io/rhel7.2
- os.template.kubevirt.io/rhel7.3
- os.template.kubevirt.io/rhel7.4
- os.template.kubevirt.io/rhel7.5
- os.template.kubevirt.io/rhel6.0
- os.template.kubevirt.io/rhel6.1
- os.template.kubevirt.io/rhel6.2
- os.template.kubevirt.io/rhel6.3
- os.template.kubevirt.io/rhel6.4
- os.template.kubevirt.io/rhel6.5
- os.template.kubevirt.io/rhel6.6
- os.template.kubevirt.io/rhel6.7
- os.template.kubevirt.io/rhel6.8
- os.template.kubevirt.io/rhel6.9
- os.template.kubevirt.io/rhel6.10

### openSUSE

- os.template.kubevirt.io/opensuse15.0

### Microsoft Windows

- os.template.kubevirt.io/win2k16
- os.template.kubevirt.io/win2k12r2
- os.template.kubevirt.io/win2k12
- os.template.kubevirt.io/win2k8r2
- os.template.kubevirt.io/win2k8
- os.template.kubevirt.io/win10
- os.template.kubevirt.io/win8.1
- os.template.kubevirt.io/win8
- os.template.kubevirt.io/win7
- os.template.kubevirt.io/winvista
- os.template.kubevirt.io/winxp

## Workload profiles

- workload.template.kubevirt.io/desktop
- workload.template.kubevirt.io/server
- workload.template.kubevirt.io/cpu-intensive
- workload.template.kubevirt.io/io-intensive
- workload.template.kubevirt.io/sap-hana

## Flavors

- flavor.template.kubevirt.io/tiny
- flavor.template.kubevirt.io/small
- flavor.template.kubevirt.io/medium
- flavor.template.kubevirt.io/large
- flavor.template.kubevirt.io/xlarge

