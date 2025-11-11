# Available labels

This file describes the labels used in the VirtualMachineTemplate resources.

## Template labels

All templates include the following labels:

- `template.kubevirt.io/type: base` - Indicates this is a base template
- `template.kubevirt.io/version: <version>` - Template version (from VERSION env var or "devel")
- `template.kubevirt.io/architecture: <arch>` - Target architecture (amd64, arm64, or s390x)
- `template.kubevirt.io/default-os-variant: "true"` - Applied to default variant of an OS (optional)

## Deprecated templates

When a template is deprecated, the following annotation is applied to it: `template.kubevirt.io/deprecated: "true"`.

The template itself is not removed for backward compatibility reasons.

## Operating system labels

The operating system labels must match the [libosinfo
identifiers](https://gitlab.com/libosinfo/osinfo-db/tree/master/data/os) from the relevant xml files (look for short-id).

### Ubuntu

- `os.template.kubevirt.io/ubuntuXX.XX` (e.g. ubuntu24.04, ubuntu22.04)

### Fedora

- `os.template.kubevirt.io/fedoraXX` (e.g. fedora40, fedora41)

### CentOS

- `os.template.kubevirt.io/centosX.X` (e.g. centos6.0)
- `os.template.kubevirt.io/centos-streamX` (e.g. centos-stream9, centos-stream10)

### Red Hat Enterprise Linux

- `os.template.kubevirt.io/rhelX.X` (e.g. rhel7.0, rhel8.0, rhel9.0, rhel10.0)

### openSUSE

- `os.template.kubevirt.io/opensuseXX.X` (e.g. opensuse15.6)

### Microsoft Windows

- `os.template.kubevirt.io/win2kXX` (e.g. win2k16, win2k19, win2k22, win2k25)
- `os.template.kubevirt.io/winXX` (e.g. win10, win11)
