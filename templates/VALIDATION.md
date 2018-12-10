# Template validation annotations

Version 201812

## Summary

We introduce and document here a new annotation format that serves as hint for CNV-aware tooling
to validate the templates.
Being built on the existing Kubernetes annotation format, the data expressed using this format
is completely optional and ignored by existing Kubernetes/Openshift services.

In order to be backward and future compatible, consumers of these annotations should ignore
the data they don't understand.

## Format

The validation hints are encoded into another template annotation, called `validation`. The value of this
annotation must be a multi-line string.
The multi-line string must be valid JSON array of validation objects. The format of the validation objects
is described below.

Example:
```yaml
validations: |
  [
    {
      valid: '/some/json/path',
      path: '/some/json/path/*/leaf',
      rule: '1',
      message: '/some/json/path/*/leaf must exists',
      min: 1
    },
    {
      valid: '/another/json/path',
      path: '/another/json/path/item',
      rule: '2',
      message: '/another/json/path/item must be below a threshold',
      max: '/yet/another/json/path/defines/the/limit'
    }
  ]
```


## Rule Format

A validation rule is expressed as JSON object which have a number of mandatory and optional keys.
The consumer of the rule should ignore any field it doesn't know how to handle.
If a rule is meaningless, for example if it has no arguments, see below, its behaviour is *unspecified*,
so the consumer is free to consider it satisfied or not.

### JSONPaths

TODO: clarify the root of the JSONPaths.

### Mandatory Keys

* `rule`: identifier (number) of the rule. Must be unique among the given set of rules.
* `path`: [jsonpath](https://kubernetes.io/docs/reference/kubectl/jsonpath/) of the field whose value is
   going to be evaluated.
* `message`: user-friendly string message describing the rule.

### Optional Keys

* `valid`: the rule must be *ignored* if the jsonpath given as value doesn't exist.

### Rule arguments (optional keys)

The following are optional keys which serve as argument of the rule. They define the actual constraint that
the rule must enforce.
A rule without any argument has undefined behaviour

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
            "valid": "/VM/domain/cpu/cores",
            "path": "/VM/domain/cpu/cores",
            "rule": "1",
            "message": "cpu cores must be limited"
            "min": 1,
            "max": 8
          }
        ]
```

#### included:
The rule is satisfied if the path item is exactly one of the element listed in the value of
this key, case sensitive. Due to current limitations of the annotations:
- the path item must be rendered as string for the purpose of the check
- the value must be a JSON array of values

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
            path: "/VM/disk/*/type",
            rule: "disks-A",
            message: "the disk bus type must be one of the supported values",
            included: ["virtio", "scsi"]
          }
        ]
```

#### minLength / maxLength

The rule is satisfied if the length of the path item rendered as string is either
- lesser or equal, for `minLength` or
- greater or equal, `for maxLength`,
than the value of the validator. Albeit legal, this constraint is probably meaningless for non-string items.

Example:
```yaml
PENDING
```
