# Template validation annotations

Version 201901-1

## Summary

We introduce and document here a new annotation format that serves as hint for CNV-aware tooling to validate the templates.
Being built on the existing Kubernetes annotation format, the data expressed using this format is completely optional and ignored by existing Kubernetes/Openshift services.

In order to be backward and future compatible, consumers of these annotations should ignore the data they don't understand.

## Format

The validations hints are encoded into another template annotation, called `validation`.
The value of this annotation must be a multi-line string.
The multi-line string must be valid JSON array of validation objects.
The format of the validation objects is described below.

Example:
```yaml
validations: |
  [
    {
      "name": "validation-rule-01",
      "valid": "/some.json.path",
      "path”: "/some.json.path[*].leaf",
      "rule”: "integer",
      "message”: "/some.json.path[*].leaf must exists",
      "min”: 1
    },
    {
      "name": "validation-rule-02",
      "valid": "/another.json.path",
      "path": "/another.json.path.item",
      "rule": "integer",
      "message": "/another.json.path.item must be below a threshold",
      "max": "/yet.another.json.path.defines.the.limit"
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
    annotations:
      validations: |
        [
          {
            "name": "core-limits",
            "path": "/spec.domain.cpu.cores",
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
    annotations:
      validations: |
        [
          {
            “rule”: “integer”,
            "path": "/spec.domain.cpu.cores",
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
    annotations:
      validations: |
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

* `valid`: the rule must be *ignored* if the jsonpath given as value doesn't exist.

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
    annotations:
      validations: |
        [
          {
            "name": "core-limits",
            "valid": "/spec.domain.cpu.cores",
            "path": "/spec.domain.cpu.cores",
            "rule": "integer",
            "message": "cpu cores must be limited"
            "min": 1,
            "max": 8
          }
        ]
```

#### included:
The rule is satisfied if the path item is exactly one of the element listed in the value of this key, case sensitive. Due to current limitations of the annotations:
- the path item must be rendered as string for the purpose of the check.
- the value must be a JSON array of values.

Example:
```yaml
apiVersion: v1
kind: Template
  metadata:
    name: windows-10
    annotations:
      validations: |
        [
          {
            "name": "supported-bus",
            "path": "/spec.devices.disks[*].type",
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
    annotations:
      validations: |
        [
          {
            "name": "non-empty-net",
            "path": "/spec.devices.interfaces[*].name",
            "rule": "string",
            "message": "the network name must be non-empty",
            "minLength": 1
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
    annotations:
      validations: |
        [
          {
            "name": "core-limits",
            "path": "spec.domain.cpu.cores",
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
    annotations:
      validations: |
        [
          {
            "name": "supported-bus",
            "valid": "spec.domain.devices.disks[*].disk",
            "path": "spec.domain.devices.disks[*].disk.bus",
            "rule": "enum",
            "message": "the disk bus type must be one of the supported values",
            "values": ["virtio", "scsi"]
          }
        ]
```

