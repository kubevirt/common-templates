SHELL=/bin/bash

# i.e. fedora28.yaml
ALL_META_TEMPLATES=$(wildcard templates/*.yaml)
ALL_TEMPLATES=$(wildcard dist/templates/*.yaml)
ALL_PRESETS=$(wildcard presets/*.yaml)
METASOURCES=$(ALL_META_TEMPLATES) $(ALL_PRESETS)

# i.e. fedora28
ALL_GUESTS=$(ALL_TEMPLATES:dist/templates/%.yaml=%)

# Make sure the version is defined
VERSION=unknown


TEST_SYNTAX=$(ALL_GUESTS)
TEST_UNIT=$(ALL_GUESTS)
ifeq ($(TEST_FUNCTIONAL),ALL)
TEST_FUNCTIONAL=fedora-generic-small ubuntu-generic-small opensuse-generic-small rhel7-generic-small centos7-generic-small
endif


test: syntax-tests unit-tests functional-tests

syntax-tests: generate $(TEST_SYNTAX:%=%-syntax-check)

unit-tests: generate is-deployed
unit-tests: $(TEST_UNIT:%=%-apply-and-remove)
unit-tests: $(TEST_UNIT:%=%-generated-name-apply-and-remove)

functional-tests: generate is-deployed
functional-tests: $(TEST_FUNCTIONAL:%=%-start-wait-for-systemd-and-stop)

dist/templates/%.yaml: generate

dist/common-templates.yaml: generate
	( \
	  echo -n "# Version " ; \
	  git describe --always --tags HEAD ; \
	  for F in $(ALL_PRESETS) dist/templates/*.yaml; \
	  do \
	    echo "---" ; \
	    echo "# Source: $$F" ; \
	    cat $$F ; \
	  done ; \
	) >$@

release: dist/common-templates.yaml
	cp dist/common-templates.yaml dist/common-templates-$(VERSION).yaml

TRAVIS_FOLD_START=echo -e "travis_fold:start:details\033[33;1mDetails\033[0m"
TRAVIS_FOLD_END=echo -e "\ntravis_fold:end:details\r"

gather-env-of-%:
	kubectl describe vm $*
	kubectl describe vmi $*
	kubectl describe pods
	kubectl -n kube-system logs -l kubevirt.io=virt-handler --tail=20

is-deployed:
	kubectl api-versions | grep kubevirt.io

generate: generate-templates.yaml $(METASOURCES)
	ansible-playbook generate-templates.yaml

%-syntax-check: dist/templates/%.yaml
	oc process --local -f "dist/templates/$*.yaml" NAME=$@ PVCNAME=$*-pvc

%-apply-and-remove: dist/templates/%.yaml
	oc process --local -f "dist/templates/$*.yaml" NAME=$@ PVCNAME=$*-pvc | \
	  kubectl apply -f -
	oc process --local -f "dist/templates/$*.yaml" NAME=$@ PVCNAME=$*-pvc | \
	  kubectl delete -f -

%-generated-name-apply-and-remove:
	oc process --local -f "dist/templates/$*.yaml" PVCNAME=$*-pvc > $@.yaml
	kubectl apply -f $@.yaml
	kubectl delete -f $@.yaml
	rm -v $@.yaml

%-start-wait-for-systemd-and-stop: %.pvc
	oc process --local -f "dist/templates/$*.yaml" NAME=$* PVCNAME=$* | \
	  kubectl apply -f -
	virtctl start $*
	$(TRAVIS_FOLD_START)
	while ! kubectl get vmi $* -o yaml | grep "phase: Running" ; do make gather-env-of-$* ; sleep 3; done
	make gather-env-of-$*
	$(TRAVIS_FOLD_END)
	# Wait for a pretty universal magic word
	virtctl console --timeout=5 $* | tee /dev/stderr | egrep -m 1 "Welcome|systemd"
	oc process --local -f "dist/templates/$*.yaml" NAME=$* PVCNAME=$* | \
	  kubectl delete -f -

pvs: $(TESTABLE_GUESTS:%=%.pv)
raws: $(TESTABLE_GUESTS:%=%.raw)

%.pvc: %.pv
	kubectl get pvc $*

# fedora-generic-small.pv will use fedora.raw
.SECONDEXPANSION:
%.pv: $$(firstword $$(subst -, ,$$@)).raw
	$(TRAVIS_FOLD_START)
	SIZEMB=$$(( $$(qemu-img info $< --output json | jq '.["virtual-size"]') / 1024 / 1024 + 128 )) && \
	mkdir -p "$$PWD/pvs/$*" && \
	ln $< $$PWD/pvs/$*/disk.img && \
	sudo chown 107:107 $$PWD/pvs/$*/disk.img && \
	sudo chmod -R a+X $$PWD/pvs && \
	bash create-minikube-pvc.sh "$*" "$${SIZEMB}M" "$$PWD/pvs/$*/" | tee | kubectl apply -f -
	find $$PWD/pvs
	kubectl get -o yaml pv $*
	$(TRAVIS_FOLD_END)

%.raw: %.qcow2
	qemu-img convert -p -O raw $< $@

fedora.qcow2:
	curl -L -o $@ https://download.fedoraproject.org/pub/fedora/linux/releases/28/Cloud/x86_64/images/Fedora-Cloud-Base-28-1.1.x86_64.qcow2

ubuntu.qcow2:
	curl -L -o $@ http://cloud-images.ubuntu.com/bionic/current/bionic-server-cloudimg-amd64.img

opensuse.qcow2:
	curl -L -o $@ https://download.opensuse.org/repositories/Cloud:/Images:/Leap_15.0/images/openSUSE-Leap-15.0-OpenStack.x86_64-0.0.4-Buildlp150.12.12.qcow2

centos7.qcow2:
	curl -L http://cloud.centos.org/centos/7/images/CentOS-7-x86_64-GenericCloud.qcow2.xz | xz -d > $@

# For now we test the RHEL75 template with the CentOS image
rhel7.raw: centos7.raw
	ln $< $@

clean:
	rm -v *.raw *.qcow2

.PHONY: all test generate release
