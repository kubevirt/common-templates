
TEMPLATES=$(wildcard templates/*.yaml)
GUESTS=$(TEMPLATES:templates/%.yaml=%)

TESTABLE_GUESTS=fedora28 ubuntu1604 opensuse15

test: $(GUESTS)

$(GUESTS): %: %.syntax-check
$(GUESTS): %: %.apply-and-remove

%.syntax-check:
	oc process --local -f "templates/$*.yaml" NAME=the-$* PVCNAME=the-$*-pvc

%.apply-and-remove:
	oc process --local -f "templates/$*.yaml" NAME=the-$* PVCNAME=the-$*-pvc | \
	  kubectl apply -f -
	oc process --local -f "templates/$*.yaml" NAME=the-$* PVCNAME=the-$*-pvc | \
	  kubectl delete -f -
	oc process --local -f "templates/$*.yaml" PVCNAME=the-$*-pvc > $*.yaml
	kubectl apply -f $*.yaml
	kubectl delete -f $*.yaml
	rm -v $*.yaml

%.pvc:
	# This is just testing, not creating, we separate creation
	kubectl get pvc $*

pvs: raws
raws: $(TESTABLE_GUESTS:%=%.raw)

%.pv: %.raw
	SIZEMB=$$(( $$(qemu-img info $< --output json | jq '.["virtual-size"]') / 1024 / 1024 + 128 )) \
	set -x ; kubectl plugin pvc create "$*" "$${SIZEMB}M" "$$PWD/$<" "disk.img"

fedora28.qcow2:
	curl -L -o $@ https://download.fedoraproject.org/pub/fedora/linux/releases/28/Cloud/x86_64/images/Fedora-Cloud-Base-28-1.1.x86_64.qcow2
fedora28.raw: fedora28.qcow2
	qemu-img convert -p -O raw $< $@

ubuntu1604.qcow2:
	curl -L -o $@ http://cloud-images.ubuntu.com/xenial/current/xenial-server-cloudimg-amd64-disk1.img
ubuntu1604.raw: ubuntu1604.qcow2
	qemu-img convert -p -O raw $< $@

opensuse15.qcow2:
	curl -L -o $@ https://download.opensuse.org/repositories/Cloud:/Images:/Leap_15.0/images/openSUSE-Leap-15.0-OpenStack.x86_64-0.0.4-Buildlp150.12.11.qcow2
opensuse15.raw: opensuse15.qcow2
	qemu-img convert -p -O raw $< $@

.PHONY: all test

clean:
	rm -v *.raw *.qcow2
