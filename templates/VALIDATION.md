# Template validation annotations

Version 201812

## Summary

We introduce and document here a new annotation format that serves as hint for CNV-aware tooling
to validate the templates.
Being built on the existing Kubernetes annotation format, the data expressed using this format
is completely optional and ignored by existing Kubernetes/Openshift services.

In order to be backward and future compatible, consumers of these annotations should ignore
the data they don't understand.
