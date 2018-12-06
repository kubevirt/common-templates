# Template development guidelines

The idea is to reuse and enhance the concept of OpenShift templates and its parameter expansion and also to reuse the kubevirt’s VM.spec structure as a DTO that will provide data to the parameter expansion.

Since the templates will contain lots of redundancies, there should be a build time templating mechanism for composing the final templates from snippets.

Also, there might be multiple different OSes, flavors, sizes mentioned by any single template file if they share the same configuration.

Please note that the cnv.io suffix used in labels and annotations is temporary and is likely to change.

## User Experience

The flow should be the same as usual with regards to openshift templates. The user either takes a local template and generates a VM object.

Or the user gets a template from kubernetes and invokes the proper REST command on top of it to keep the VM linked to the template or edit it in accordance to the template.

The UI can then operate on top of template parameters and/or the Template.VM.spec DOM directly. There is an openshift [REST endpoint for instantiating Templates](https://docs.openshift.com/container-platform/3.7/rest_api/examples.html#template-instantiation) and the UI might be able to use it to create an in memory instance of VM it will then work with before posting it (kubernetes dry-run issues [https://github.com/kubernetes/kubernetes/issues/11488](#11488) and [https://github.com/kubernetes/kubernetes/issues/63559](#63559)).

## Example file

### template.yaml

```YAML
# vim: sts=2 sw=2 et
apiVersion: v1
kind: Template # Openshift kind of template or something "better"
metadata:
  name: windows-10
  annotations:
    openshift.io/display-name: "Generic Microsoft Windows 7+ template"
    description: "Basic windows template long description with details"
    openshift.io/long-description: >-
      Long description of the template
    openshift.io/provider-display-name: "Red Hat, Inc."
    openshift.io/documentation-url: "https://cnv.io/..."
    openshift.io/support-url: "https://access.redhat.com"
    iconClass: icon-windows    

    # Template structure version
    template.cnv.io/version: v1alpha1

    # The `defaults` set of annotations is meant as a hint only
    # and is not going to be processed by the stock openshift templating
    # mechanism. CNV UI can and should use it though.
    # The information encoded there informs the tooling (UI)
    # about names of devices that are to be used as templates
    # for adding additional disk, networks, volumes and such

    # The goal of default disk is to define what kind of disk
    # is supported by the OS mainly in terms of bus (ide, scsi,
    # sata, virtio, ...)
    defaults.template.cnv.io/disk: default-disk

    # The goal of default volume is to be able to configure mostly
    # performance parameters like caches if those are exposed
    # by the underlying volume implementation.
    defaults.template.cnv.io/volume: default-volume

    # The goal of default network is similar to default-disk
    # and should be used as a template to ensure OS compatibility
    # and performance
    defaults.template.cnv.io/nic: default-nic

    # The goal of default network is similar to default-volume
    # and should be used as a template that specifies performance
    # and connection parameters (L2 bridge for example)
    defaults.template.cnv.io/network: default-network

    # Extension for hinting at which elements should be
    # considered editable. The content is a line separated
    # list of jsonpath selectors.
    # The jsonpath root is the objects: element of the template
    template.cnv.io/editable: |
      /objects[0].spec.template.spec.domain.cpu.cores
      /objects[0].spec.template.spec.domain.resources.requests.memory
      /objects[0].spec.template.spec.domain.devices.disks
      /objects[0].spec.template.spec.volumes
      /objects[0].spec.template.spec.networks

    # You can add an extension useful for CNV aware tooling to allow
    # expressing additional validation rules for this template.
    # See the separate 'VALIDATION.md' document for the specification.

  labels:
    # The UI can show all possible template.cnv.io/* values in a nice way
    # and let the user filter down the available templates to the one
    # the user actually wants:
    # A single selected template only means no conflicts and no smart
    # merging code. This has to be done using labels to allow efficient
    # searching.
    # The format has the following meaning:
    # {os,flavor,size}.template.cnv.io/{value}: true (or false for exclusion)
    # OS names should match the libosinfo identifiers
    # flavors are tiny, medium, large, etc.
    # workloads are generic, high-performance, io-intensive,
    #               oracle-db, sap-hana...
    os.template.cnv.io/windows2k12r2: "true"
    os.template.cnv.io/windows8: "true"
    os.template.cnv.io/windows7: "true"
    workload.template.cnv.io/minimal: "true"
    workload.template.cnv.io/io-intensive: "true"
    # flavor.template.cnv.io/* not specified means all
    # And example of not specifying any positive requirement
    # but listing the exclusions instead (matches all except
    # the listed false valued labels).
    flavor.template.cnv.io/tiny: "false"

    # CNV Template type to separate the use cases for base OS,
    # flavor, sizing templates and templates created from
    # running or imported VMs.
    # The supported values are currently: base and vm
    template.cnv.io/type: "base"

# Parameters must come from a subset of well known names
# so the UI can properly work with those.
parameters:
- name: NAME
  description: VM name
  generate: expression
  from: 'vm-[A-Za-z0-9]{8}'
- name: MEMORY_SIZE
  description: Memory size
  value: 1Gi

objects:
# The full VM template with placeholders for either scalars like memory
# or yaml structures like disks
- apiVersion: kubevirt.io/v1alpha2
  kind: VirtualMachine
  metadata:
    name: ${NAME}
  spec:
    running: false
    template:
      spec:
        domain:
          resources:
            initial:
              memory: ${MEMORY_SIZE}Mi
          devices:
            disks:
            # This should be interpreted as a template disk by the UI,
            # thanks to the template.cnv.io/default annotations
            # This must still result in a bootable VM when used as is.
            # This way we can both use Templates for creating new VM as well
            # as for converting an existing VM to a template
            - name: default-disk
              disk:
                dev: vda
              volumeName: default-volume

            interfaces:
            # This should be interpreted as a template network by the UI,
            # thanks to the template.cnv.io/default annotations
            # This must still result in a bootable VM when used as is.
            # This way we can both use Templates for creating new VM as well
            # as for converting an existing VM to a template
            - type: pod-network
              name: default-nic
              model:
                type: virtio

        networks:
          - name: default-network
            resource:
              resourceName: bridge.network.kubevirt.io/cnvmgmt

        volumes:
            # This should be interpreted as a template volume by the UI,
            # thanks to the template.cnv.io/default annotations
            # This must still result in a bootable VM when used as is.
            # This way we can both use Templates for creating new VM as well
            # as for converting an existing VM to a template
          - name: default-volume
            registryDisk:
              image: test/image

```

### VM.yaml

The above template should result in the following VM object:

```YAML
# vim: sts=2 sw=2 et
apiVersion: kubevirt.io/v1alpha2
kind: VirtualMachine
metadata:
  name: windows-10-1
  annotations:
    # Data used for the UI, ignored by kubevirt
    # Arbitrary format as needed to be able to
    # repopulate the UI or the template processor
    # and get the same output
    parameters.template.cnv.io/MEMORY_SIZE: 8

    # Extension for specifying which elements were customized.
    # The idea is to record fields that need to be preserved
    # during spec replacement happening as part of Template
    # editing or upgrade.
    # The content is a line separated list of jsonpath selectors.
    # The jsonpath root is the spec: element of the VM object
    template.cnv.io/keep: |
      /template.spec.domain.cpu.cores
      /template.spec.domain.resources.requests.memory
      /template.spec.domain.devices.disks
      /template.spec.volumes
      /template.spec.networks

  labels:
    # This labels will link the VM to a template that was
    # used to create it. This can be then used by the user
    # or UI for recomputing the VM.spec using updated
    # template. A VM without this label can be considered
    # "baked" and not linked to any template.
    vm.cnv.io/template: windows

    # This optional label will link the VM to the namespace
    # of a template that was used to create it.
    # If this label is not defined, the template is 
    # expected to belong to the same namespace as the VM.
    vm.cnv.io/template-namespace: openshift

# The requested state of the VM that will always match what
# the user asked for exactly. When the UI pushes edits it
# simply replaces the whole spec: with the current version
# the user saved
spec:
  running: false
  template:
    spec:
      domain:
        resources:
          initial:
            memory: 8Mi
        devices:
          disks:
          - name: default-disk
            disk:
              dev: vda
            volumeName: default-volume

          interfaces:
          - type: pod-network
            name: default-network
            model:
              type: virtio

      volumes:
      - name: default-volume
        registryDisk:
          image: test/image

status:
  devices:
    # Roman's idea I like:
    # This block should contain the backpropagated
    # addresses needed for keeping the device ordering stable.
    # The user defined addresses in VM.spec have higher priority.
    # The values here should be used during the VM -> VMI conversion
    # or later (VMI -> domxml) and the VM.spec should only contain
    # the values user requested as is.
    disk0:
      scsi-id: X.Y.Z
    disk1:
      scsi-id: X.Y.Z
    nic0:
      pci-id: X.Y.Z
    nic0:
      mac-address: AA:BB:CC:DD:EE:FF
```

## Future enhancements

- Parameter replacement could support numerical expressions (either in the template or during parameter definition - one parameter building on top of another)

## Open questions

- How and when should we propagate Template changes to already created VMs. I assume a new controller will be created to watch for changes and inform / apply them as needed.


[//]: # vim: et sw=2 sts=2

