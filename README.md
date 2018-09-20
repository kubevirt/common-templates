[![Build Status](https://travis-ci.com/kubevirt/common-templates.svg?branch=master)](https://travis-ci.com/kubevirt/common-templates)

A set of Templates to create KubeVirt VMs.

# Overview

All VMs are provided as [OpenShift templates](https://docs.okd.io/latest/dev_guide/templates.html).
These templates can be used straight forward with OpenShift itself, or they
can be transformed into regular objects for use with Kubernetes.

Every template consists of two objects:

1. A VirtualMachineInstancePreset definition for the specific guest, this is
   comparable to a "flavor"
2. A VirtualMachine definition which can be used to launch the guest, if a disk
   image is available (see below)

The presets allow to keep all the guest specific machine configuration in a
single place. This configuration is applied to the VMs once they are started.

# Usage

By default the snippets below from the table will fetch the template and
process it. It fails if a parameter (like the PVC name) is required, but not
provided. In such a case the parameter is appended to the snippet, i.e.
`PVCNAME`.

```bash
# Define the generic instance types:
$ kubectl apply -f https://raw.githubusercontent.com/fabiand/common-templates/master/presets/instancetypes.yaml

$ oc process --local -f https://git.io/fNp4Z
The Template "win2k12r2" is invalid: template.parameters[1]: Required value:
template.parameters[1]: parameter PVCNAME is required and must be specified

$ oc process --local -f https://git.io/fNp4Z  --parameters
NAME      DESCRIPTION                           GENERATOR   VALUE
NAME      Name of the new VM                    expression  windows2012r2-[a-z0-9]{6}
PVCNAME   Name of the PVC with the disk image

$ oc process --local -f https://git.io/fNp4Z PVCNAME=mydisk
…

$ oc process --local -f https://git.io/fNp4Z PVCNAME=mydisk | kubectl apply -f -
virtualmachineinstancepreset.kubevirt.io/win2k12r2 created
virtualmachine.kubevirt.io/windows2012r2-rt1ap2 created

$
```

# Templates

> **Note:** The templates are tuned for a specific guest version, but is often
> usable with different versions as well, i.e. the Fedora 28 template is also
> usable with Fedora 27 or 26.

| Template | Snippet |
|---|---|
| Microsoft Windows Server 2012 R2 (no CI) | [`oc process --local -f https://git.io/fNp4Z`](templates/win2k12r2.yaml) |
| Fedora 28 | [`oc process --local -f https://git.io/fNpBU`](templates/fedora28.yaml) |
| Red Hat Enterprise Linux 7.5 | [`oc process --local -f https://git.io/fNpuq`](templates/rhel75.yaml) |
| Ubuntu 18.04 LTS | [`oc process --local -f https://git.io/fA4q5`](templates/ubuntu1804.yaml) |
| OpenSUSE Leap 15.0 (no CI) | [`oc process --local -f https://git.io/fNpz2`](templates/opensuse15.yaml) |
| CoreOS Container Linux | TBD |
