[![Build Status](https://travis-ci.com/kubevirt/common-templates.svg?branch=master)](https://travis-ci.com/kubevirt/common-templates)

A set of (meta-)Templates to create KubeVirt VMs.

# Overview

This repository provides VM templates in the form compatible with [OpenShift templates](https://docs.okd.io/latest/dev_guide/templates.html) and kubevirt UI and those can further be transformed into regular objects for use with plain Kubernetes.

The VM templates are generated from [meta-templates](templates/) via [Ansible](https://www.ansible.com/) and [libosinfo](https://libosinfo.org/). The generated templates are parametrized according to three aspects: the guest OS, the workload type and the size. The generated content is stored in [dist/](dist/).

The [Ansible playbook](https://docs.ansible.com/ansible/latest/user_guide/playbooks.html) [generate-templates.yaml](generate-templates.yaml) describes all combinations that should be generated.

Every template consists of a VirtualMachine definition which can be used to launch the guest, if a disk image is available (see below).

# Requirements

Is it necessary to install the following components to be able to run the Ansible generator and the CI suite:

- jq
- ansible >= 2.4
- libosinfo
- python-gobject
- osinfo-db-tools
- intltool

# Usage

By default the process below takes a generated template and converts it to an VM object that can be used to start a virtual machine.
The conversion fails if a parameter (like the PVC name) is required, but not
provided (i.e.`PVCNAME`).

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
# - the guest OS - win2k12r2
# - the workload type - desktop
# - the size - medium

# Use the template
$ oc process --local -f dist/templates/win2k12r2-desktop-medium.yaml
The Template "win2k12r2-desktop-medium" is invalid: template.parameters[1]: Required value:
template.parameters[1]: parameter PVCNAME is required and must be specified

$ oc process --local -f dist/templates/win2k12r2-desktop-medium.yaml  --parameters
NAME      DESCRIPTION                           GENERATOR   VALUE
NAME      Name of the new VM                    expression  windows2012r2-[a-z0-9]{6}
PVCNAME   Name of the PVC with the disk image

$ oc process --local -f dist/templates/win2k12r2-desktop-medium.yaml PVCNAME=mydisk
…

$ oc process --local -f dist/templates/win2k12r2-desktop-medium.yaml PVCNAME=mydisk | kubectl apply -f -
virtualmachine.kubevirt.io/windows2012r2-rt1ap2 created

$
```

# Templates

The table below lists the guest operating systems that are covered by the templates. The meta-templates are not directly consumable, please use the [generator](generate-templates.yaml) to prepare the properly parametrized templates first.

> **Note:** The templates are tuned for a specific guest version, but is often
> usable with different versions as well, i.e. the Fedora 28 template is also
> usable with Fedora 27 or 26.

| Guest OS | Meta-template |
|---|---|
| Microsoft Windows Server 2012 R2 (no CI) | [win2k12r2](templates/win2k12r2.tpl.yaml) |
| Fedora 28 | [fedora](templates/fedora.tpl.yaml) |
| Red Hat Enterprise Linux 7.5 | [rhel7](templates/rhel7.tpl.yaml) |
| Ubuntu 18.04 LTS | [ubuntu](templates/ubuntu.tpl.yaml) |
| OpenSUSE Leap 15.0 (no CI) | [opensuse](templates/opensuse.tpl.yaml) |
| Cent OS 7 | [centos7](templates/centos7.tpl.yaml) |

# License

common-templates are  distributed under the
[Apache License, Version 2.0](http://www.apache.org/licenses/LICENSE-2.0.txt).

