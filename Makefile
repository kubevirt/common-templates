
ALL_TEMPLATES=$(wildcard templates/*.yaml)

ALL_GUESTS=$(ALL_TEMPLATES:templates/%.yaml=%)

$(ALL_GUESTS): %: %.syntax-check
$(ALL_GUESTS): %: %.apply-and-remove
$(ALL_GUESTS): %: %.generated-name-apply-and-remove

ifdef WITH_FUNCTIONAL
TESTABLE_GUESTS=fedora28 ubuntu1604 opensuse15
$(TESTABLE_GUESTS): %: %.start-and-stop
endif

test: $(ALL_GUESTS)

%.syntax-check: templates/%.yaml
	oc process --local -f "templates/$*.yaml" NAME=the-$* PVCNAME=the-$*-pvc

%.apply-and-remove:
	oc process --local -f "templates/$*.yaml" NAME=the-$* PVCNAME=the-$*-pvc | \
	  kubectl apply -f -
	oc process --local -f "templates/$*.yaml" NAME=the-$* PVCNAME=the-$*-pvc | \
	  kubectl delete -f -

%.generated-name-apply-and-remove:
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

centos7.qcow2:
	curl -L http://cloud.centos.org/centos/7/images/CentOS-7-x86_64-GenericCloud.qcow2.xz | xz -d > $@
centos7.raw: centos7.qcow2
	qemu-img convert -p -O raw $< $@

# For now we test the RHEL75 template with the CentOS image
rhel75.raw: centos7.raw
       ln $< $@

clean:
	rm -v *.raw *.qcow2

.PHONY: all test
