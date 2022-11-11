# kubevirt/common-templates

A set of (meta-)Templates to create KubeVirt VMs.

## Overview

This repository provides VM templates in the form compatible with [OpenShift templates](https://docs.okd.io/latest/openshift_images/using-templates.html) and OpenShift Cluster Console Web UI and those can further be transformed into regular objects for use with plain Kubernetes.

The VM templates are generated from [meta-templates](templates/) via [Ansible](https://www.ansible.com/) and [libosinfo](https://libosinfo.org/). The generated templates are parametrized according to three aspects: the guest OS, the workload type and the size. The generated content is stored in [dist/](dist/).

The [Ansible playbook](https://docs.ansible.com/ansible/latest/user_guide/playbooks.html) [generate-templates.yaml](generate-templates.yaml) describes all combinations that should be generated.

Every template consists of a VirtualMachine definition which can be used to launch the guest, if a disk image is available (see below).

## Requirements

Is it necessary to install the following components to be able to run the Ansible generator and the CI suite:

- jq
- ansible >= 2.4
- libosinfo
- python-gobject
- osinfo-db-tools
- intltool

## Usage

By default the process below takes a generated template and converts it to an VM object that can be used to start a virtual machine.

```bash
# Clone the repository
$ git clone https://github.com/kubevirt/common-templates
$ cd common-templates

# Pull all submodules
$ git submodule init
$ git submodule update

# Build osinfo database
$ make -C osinfo-db

# Generate the template matrix
$ ansible-playbook generate-templates.yaml

# Pick a template by selecting
# - the guest OS - windows
# - the workload type - desktop
# - the size - medium

# Use the template
$ oc process --local -f dist/templates/windows10-desktop-medium.yaml

$ oc process --local -f dist/templates/windows10-desktop-medium.yaml  --parameters
NAME                    DESCRIPTION                       GENERATOR           VALUE
NAME                    VM name                           expression          windows-[a-z0-9]{6}
DATA_SOURCE_NAME        Name of the DataSource to clone                       win10
DATA_SOURCE_NAMESPACE   Namespace of the DataSource                           kubevirt-os-images

$ oc process --local -f dist/templates/windows10-desktop-medium.yaml | kubectl apply -f -
virtualmachine.kubevirt.io/windows10-rt1ap2 created

$
```

## Templates

The table below lists the guest operating systems that are covered by the templates. The meta-templates are not directly consumable, please use the [generator](generate-templates.yaml) to prepare the properly parametrized templates first.

> **Note:** The templates are tuned for a specific guest version, but is often
> usable with different versions as well, i.e. the Fedora 34 template is also
> usable with Fedora 35.

| Guest OS | Meta-template |
|---|---|
| Microsoft Windows Server 2012 R2 | [windows2k12](templates/windows2k12.tpl.yaml) |
| Microsoft Windows Server 2016 | [windows2k16](templates/windows2k16.tpl.yaml) |
| Microsoft Windows Server 2019 | [windows2k19](templates/windows2k19.tpl.yaml) |
| Microsoft Windows Server 2022 | [windows2k22](templates/windows2k22.tpl.yaml) |
| Microsoft Windows 10 | [windows10](templates/windows10.tpl.yaml) |
| Microsoft Windows 11 | [windows11](templates/windows11.tpl.yaml) |
| Fedora | [fedora](templates/fedora.tpl.yaml) |
| Red Hat Enterprise Linux 7 | [rhel7](templates/rhel7.tpl.yaml) |
| Red Hat Enterprise Linux 8 | [rhel8](templates/rhel8.tpl.yaml) |
| Red Hat Enterprise Linux 9 Beta | [rhel9](templates/rhel9.tpl.yaml) |
| Ubuntu | [ubuntu](templates/ubuntu.tpl.yaml) |
| openSUSE Leap | [opensuse](templates/opensuse.tpl.yaml) |
| CentOS 7 | [centos7](templates/centos7.tpl.yaml) |
| CentOS Stream 8 | [centos-stream8](templates/centos-stream8.tpl.yaml) |
| CentOS Stream 9 | [centos-stream9](templates/centos-stream9.tpl.yaml) |

## License

common-templates are  distributed under the
[Apache License, Version 2.0](http://www.apache.org/licenses/LICENSE-2.0.txt).
