[![Build Status](https://travis-ci.com/fabiand/common-templates.svg?branch=master)](https://travis-ci.com/fabiand/common-templates)

A set of OpenShift Templates to create KubeVirt VMs.

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

# Templates

> **Note:** Add `--parameters` to the snippets below to learn about all
> parameters of a template


By default the snippets will fetch the template and process it. It fails if
a parameter (like the PVC name) is required, but not provided. In such a case
the parameter is appended to the snippet, i.e. `PVCNAME`:

`oc process --local -f https://git.io/fNp4Z` **`PVCNAME=mydisk`**


| Template | Description | Snippet |
|---|---|---|
| Microsoft Windows Server 2012 R2 (win2k12r2) | For this and other versions | `oc process --local -f https://git.io/fNp4Z` |
| Fedora 28 | For this and other versions | `oc process --local -f https://git.io/fNpBU` |
| Red Hat Enterprise Linux 7.5 | For this and other versions | `oc process --local -f https://git.io/fNpBq` |
| Ubuntu | | TBD |
| OpenSuse | | TBD |

## Creation of VMs

If the object shall be created right away then the output can be piped to
`kubectl`:

```bash
oc process … | kubectl apply -f -
```
