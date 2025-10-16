# kubevirt/common-templates

A set of (meta-)Templates to create KubeVirt VMs.

## Overview

This repository provides VM templates in the form of
[KubeVirt VirtualMachineTemplates](https://github.com/kubevirt/virt-template).

The VM templates are generated from [meta-templates](templates/) via
[Ansible](https://www.ansible.com/) and [libosinfo](https://libosinfo.org/). The
generated templates use
[instancetypes and preferences](https://kubevirt.io/user-guide/virtual_machines/instancetypes/)
to define VM resource sizing and runtime preferences. The generated content is
stored in [dist/](dist/).

The [Ansible playbook](https://docs.ansible.com/ansible/latest/user_guide/playbooks.html) [generate-templates.yaml](generate-templates.yaml)
describes all combinations that should be generated.

Every template consists of a VirtualMachine definition which can be used to
launch the guest, if a disk image is available (see below).

## Requirements

It is necessary to install the following components to be able to run the
Ansible generator and the CI suite:

- jq
- ansible >= 2.4
- libosinfo
- python-gobject
- osinfo-db-tools
- intltool

## Usage

By default the process below takes a generated template and converts it to a VM
object that can be used to start a virtual machine.

```bash
# Clone the repository
$ git clone https://github.com/kubevirt/common-templates
$ cd common-templates

# Pull all submodules
$ git submodule init
$ git submodule update

# Generate the templates
$ make generate

# Pick a template by selecting the guest OS - e.g. windows10

# Use the template
$ virttemplatectl process --local -f dist/templates/windows10.yaml

$ virttemplatectl process --local -f dist/templates/windows10.yaml --parameters
NAME                    DESCRIPTION                       GENERATOR           VALUE
NAME                    VM name                           expression          windows10-[a-z0-9]{5}
DATA_SOURCE_NAME        Name of the DataSource to clone                       win10
DATA_SOURCE_NAMESPACE   Namespace of the DataSource                           kubevirt-os-images
INSTANCETYPE            Instance type of the VM                               u1.medium
INSTANCETYPE_KIND       The kind of the Instance type                         VirtualMachineClusterInstancetype

$ virttemplatectl process --local -f dist/templates/windows10.yaml | kubectl apply -f -
virtualmachine.kubevirt.io/windows10-rt1ap created
```

## Templates

The table below lists the guest operating systems that are covered by the
templates. The meta-templates are not directly consumable, please use
the [generator](generate-templates.yaml) to prepare the properly parametrized
templates first.

> **Note:** The templates are tuned for a specific guest version, but are often
> usable with different versions as well, e.g. the Fedora 40 template is also
> usable with Fedora 41.

| Guest OS                                                  | Meta-template                         |
|-----------------------------------------------------------|---------------------------------------|
| Microsoft Windows (Server 2016, 2019, 2022, 2025, 10, 11) | [windows](templates/windows.tpl.yaml) |
| Red Hat Enterprise Linux (7, 8, 9, 10)                    | [linux](templates/linux.tpl.yaml)     |
| CentOS (6, Stream 9, Stream 10)                           | [linux](templates/linux.tpl.yaml)     |
| Fedora                                                    | [linux](templates/linux.tpl.yaml)     |
| Ubuntu                                                    | [linux](templates/linux.tpl.yaml)     |
| openSUSE Leap                                             | [linux](templates/linux.tpl.yaml)     |

## License

common-templates are distributed under the
[Apache License, Version 2.0](http://www.apache.org/licenses/LICENSE-2.0.txt).
