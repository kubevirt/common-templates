# Template validation annotations

Version 201902-2

## Summary

We introduce and document here a new annotation format that serves as hint for CNV-aware tooling to validate the templates.
Being built on the existing Kubernetes annotation format, the data expressed using this format is completely optional and ignored by existing Kubernetes/Openshift services.

In order to be backward and future compatible, consumers of these annotations should ignore the data they don't understand.

## Format

The validations hints are encoded into another VM annotation, called `vm.kubevirt.io/validations`.
The value of this annotation must be a multi-line string.
The multi-line string must be valid JSON array of validation objects.
The format of the validation objects is described below.

Example:
```yaml
vm.kubevirt.io/validations: |
  [
    {
      "name": "validation-rule-01",
      "valid": "jsonpath::.some.json.path",
      "path”: "jsonpath::.some.json.path[*].leaf",
      "rule”: "integer",
      "message”: ".some.json.path[*].leaf must exists",
      "min”: 1,
      "justWarning": true
    },
    {
      "name": "validation-rule-02",
      "valid": "jsonpath::.another.json.path",
      "path": "jsonpath::.another.json.path.item",
      "rule": "integer",
      "message": "jsonpath::./another.json.path.item must be below a threshold",
      "max": "jsonpath::.yet.another.json.path.defines.the.limit"
    }
  ]
```

See below for a list of realistic, well formed examples


## Rule Format

A validation rule is expressed as JSON object which have a number of mandatory and optional keys.
The consumer of the rule should ignore any field it doesn't know how to handle.
If a rule is meaningless, for example if it has no arguments (see below), its behaviour is *unspecified*, so the consumer is free to consider it satisfied or not.

### JSONPaths

For every jsonpath mentioned in this document, unless specified otherwise, the root is the objects: element of the template.
Unless otherwise specified, the value to be used as jsonpath must be prefixed with the `jsonpath::` literal.
Otherwise, the value will be interpreted as string literal.
Please note: this rule is universal. Fields that *require* a JSONPath -not a string literal- like the "Path" key, still *must* have
the `jsonpath::` prefix.

good:
```
jsonpath::.spec.domain.memory.guest
```

bad:
```
.spec.domain.memory.guest
```

### Validation rules

Each rule is meant to express a constraint. The `rule` mandatory key (see below) must be one of the available constraints:
* `integer`: the rule enforces the target to be an integer.
* `string`: the rule enforces the target to be a string.
* `regex`: the rule enforces the target to match the given regular expression.
* `enum`: the rule enforces the target to be exactly one of the given values.

If the consumer encounters a rule it doesn’t know how to handle, it should
ignore it.

### Mandatory Keys

* `rule`: validation rule name. See below for a list of possible validation rules.
* `name`: identifier (string) of the rule. Must be unique among all the rules attached to a template.
* `path`: [jsonpath](https://kubernetes.io/docs/reference/kubectl/jsonpath/) of the field whose value is going to be evaluated.
* `message`: user-friendly string message describing the failure, should the rule not be satisfied.

The following examples demonstrate invalid validation annotations. All of them lack one or more mandatory keys.

Example: lacks “rule”
```yaml
apiVersion: v1
kind: Template
metadata:
  name: windows-10
objects:
- apiVersion: kubevirt.io/v1
  kind: VirtualMachine
  metadata:
    annotations:
      vm.kubevirt.io/validations: |
        [
          {
            "name": "core-limits",
            "path": "jsonpath::.spec.domain.cpu.cores",
            "message": "cpu cores must be limited",
            "min": 1,
            "max": 8
          }
        ]
```

Example: lacks “name”, “message”
```yaml
apiVersion: v1
kind: Template
metadata:
  name: windows-10
objects:
- apiVersion: kubevirt.io/v1
  kind: VirtualMachine
  metadata:
    annotations:
      vm.kubevirt.io/validations: |
        [
          {
            “rule”: “integer”,
            "path": "jsonpath::.spec.domain.cpu.cores",
            "min": 1,
            "max": 8
          }
        ]
```

Example: lacks “path”
```yaml
apiVersion: v1
kind: Template
metadata:
  name: windows-10
objects:
- apiVersion: kubevirt.io/v1
  kind: VirtualMachine
  metadata:
    annotations:
      vm.kubevirt.io/validations: |
        [
          {
            "rule": "integer",
            "name": "core-limits",
            "message": "cpu cores must be limited",
            "min": 1,
            "max": 8
          }
        ]
```


### Optional Keys

* `justWarning`: violating rule with justWarning field set will emit a warning only instead of failing the validation.
* `valid`: the rule must be *ignored* if the jsonpath given as value doesn't exist.
  Some of the fields of the template have default values so they always exist, and setting this path to one of these fields
  has no effect.
  *PLEASE NOTE* that even if values of this key are required to be JSONPaths, you still need to use the `jsonpath::` prefix
  as explained above.
  These are some of the fields with default values:
  * `.spec.domain.cpu.sockets`
  * `.spec.domain.cpu.cores`
  * `.spec.domain.cpu.threads`
  * `.spec.domain.machine.type`
  * `.spec.domain.devices.disks[*].serial`
  * `.spec.domain.devices.disks[*].cache`
  * `.spec.domain.devices.disks[*].io`
  * `.spec.domain.devices.disks[*].tag`
  * `.spec.domain.devices.interfaces[*].model`
  * `.spec.domain.devices.interfaces[*].macAddress`
  * `.spec.domain.devices.interfaces[*].pciAddress`
  * `.spec.domain.devices.interfaces[*].tag`
  * `.spec.domain.devices.interfaces[*].ports[*].protocol`
  * `.spec.domain.devices.interfaces[*].ports[*].port`

### Rule arguments (optional keys)

The following are optional keys which serve as argument of the rule. They define the actual constraint that the rule must enforce.
A rule without any argument has undefined behaviour.

The *value* of those key may be another [jsonpath](https://kubernetes.io/docs/reference/kubectl/jsonpath/).
The jsonpath must be evaluated to fetch the effective value of the argument, to be use to evaluate the rule.

#### min / max
if present, the rule is satisfied if all the values of the affected fields are either
- greater or equal, for `min` or
- less or equal, for `max`,
than the given value.
Comparison for non-numeric values is left unspecified.

Example:
```yaml
apiVersion: v1
kind: Template
metadata:
  name: windows-10
objects:
- apiVersion: kubevirt.io/v1
  kind: VirtualMachine
  metadata:
    annotations:
      vm.kubevirt.io/validations: |
        [
          {
            "name": "core-limits",
            "valid": "jsonpath::.spec.domain.cpu",
            "path": "jsonpath::.spec.domain.cpu.cores",
            "rule": "integer",
            "message": "cpu cores must be limited"
            "min": 1,
            "max": 8
          }
        ]
```

#### values:
The rule is satisfied if the path item is exactly one of the element listed in the value of this key, case sensitive. Due to current limitations of the annotations:
- the path item must be rendered as string for the purpose of the check.
- the value must be a JSON array of values.

Example:
```yaml
apiVersion: v1
kind: Template
metadata:
  name: windows-10
objects:
- apiVersion: kubevirt.io/v1
  kind: VirtualMachine
  metadata:
    annotations:
      vm.kubevirt.io/validations: |
        [
          {
            "name": "supported-bus",
            "path": "jsonpath::.spec.devices.disks[*].type",
            "rule": "enum",
            "message": "the disk bus type must be one of the supported values",
            "values": ["virtio", "scsi"]
          }
        ]
```

#### minLength / maxLength

The rule is satisfied if the length of the path item rendered as string is either
- lesser or equal, for `minLength` or
- greater or equal, `for maxLength`,
than the value of the validator.
Albeit legal, this constraint is probably meaningless for non-string items.

Example:
```yaml
apiVersion: v1
kind: Template
metadata:
  name: windows-10
objects:
- apiVersion: kubevirt.io/v1
  kind: VirtualMachine
  metadata:
    annotations:
      vm.kubevirt.io/validations: |
        [
          {
            "name": "non-empty-net",
            "path": "jsonpath::.spec.devices.interfaces[*].name",
            "rule": "string",
            "message": "the network name must be non-empty",
            "minLength": 1
          }
        ]

```

### regex:
The rule is satisfied if the path item matches the Perl-Compatible Regular Expression which is the value of this key.
Example:
```yaml
apiVersion: v1
kind: Template
metadata:
  name: windows-10
objects:
- apiVersion: kubevirt.io/v1
  kind: VirtualMachine
  metadata:
    annotations:
      vm.kubevirt.io/validations: |
        [
          {
            "name": "supported-bus",
            "path": "jsonpath::.spec.devices.disks[*].type",
            "rule": "regex",
            "message": "the disk bus type must be one of the supported values",
            "regex": "(?mi)^virtio|scsi$"
          }
        ]
```

### justWarning:
The validation normally fails when a rule is not satisfied. The behaviour can be changed per rule by setting the `justWarning` property of the rule. The validator will then emit a warning only and the overall result of the validation will be unaffected by the rule.
Example:
```yaml
apiVersion: v1
kind: Template
metadata:
  name: windows-10
objects:
- apiVersion: kubevirt.io/v1
  kind: VirtualMachine
  metadata:
    annotations:
      vm.kubevirt.io/validations: |
        [
          {
            "name": "supported-bus",
            "valid": "jsonpath::.spec.domain.devices.disks[*].disk.bus",
            "path": "jsonpath::.spec.domain.devices.disks[*].disk.bus",
            "rule": "enum",
            "message": "the disk bus type must be one of the supported values",
            "values": ["virtio", "scsi"],
            "justWarning": true
          }
        ]
```

### Examples

The following examples are meant to describe realistic well formed annotations.

```yaml
apiVersion: v1
kind: Template
metadata:
  name: windows-10
objects:
- apiVersion: kubevirt.io/v1
  kind: VirtualMachine
  metadata:
    annotations:
      vm.kubevirt.io/validations: |
        [
          {
            "name": "core-limits",
            "path": "jsonpath::.spec.domain.cpu.cores",
            "message": "cpu cores must be limited",
            "rule": "integer",
            "min": 1,
            "max": 8
          }
        ]
```

```yaml
apiVersion: v1
kind: Template
metadata:
  name: linux-bus-types
objects:
- apiVersion: kubevirt.io/v1
  kind: VirtualMachine
  metadata:
    annotations:
      vm.kubevirt.io/validations: |
        [
          {
            "name": "supported-bus",
            "valid": "jsonpath::.spec.domain.devices.disks[*].disk.bus",
            "path": "jsonpath::.spec.domain.devices.disks[*].disk.bus",
            "rule": "enum",
            "message": "the disk bus type must be one of the supported values",
            "values": ["virtio", "scsi"],
            "justWarning": true
          }
        ]
```
