SHELL=/bin/bash

# i.e. fedora28.yaml
ALL_TEMPLATES=$(wildcard templates/*.yaml)
ALL_PRESETS=$(wildcard presets/*.yaml)
SOURCES=$(ALL_TEMPLATES) $(ALL_PRESETS)

# i.e. fedora28
ALL_GUESTS=$(ALL_TEMPLATES:templates/%.yaml=%)


TEST_SYNTAX=$(ALL_GUESTS)
TEST_UNIT=$(ALL_GUESTS)
ifeq ($(TEST_FUNCTIONAL),ALL)
TEST_FUNCTIONAL=fedora28 ubuntu1804 opensuse15 rhel75
endif


test: syntax-tests unit-tests functional-tests

syntax-tests: $(TEST_SYNTAX:%=%-syntax-check)

unit-tests: is-deployed
unit-tests: $(TEST_UNIT:%=%-apply-and-remove)
unit-tests: $(TEST_UNIT:%=%-generated-name-apply-and-remove)

functional-tests: is-deployed
functional-tests: $(TEST_FUNCTIONAL:%=%-start-and-stop)

common-templates.yaml: $(SOURCES)
	( \
	  git describe --always --tags HEAD ; \
	  for F in $(SOURCES) ; \
	  do \
	    echo "---" ; \
	    echo "# Source: $$F" ; \
	    cat $$F ; \
	  done ; \
	) | tee $@

TRAVIS_FOLD_START=echo -e "travis_fold:start:details\033[33;1mDetails\033[0m"
TRAVIS_FOLD_END=echo -e "\ntravis_fold:end:details\r"

gather-env-of-%:
	kubectl describe vm $*
	kubectl describe vmi $*
	kubectl describe pods
	kubectl -n kube-system logs -l kubevirt.io=virt-handler --tail=20

is-deployed:
	kubectl api-versions | grep kubevirt.io

%-syntax-check: templates/%.yaml
	oc process --local -f "templates/$*.yaml" NAME=$@ PVCNAME=$@-pvc

%-apply-and-remove: templates/%.yaml
	oc process --local -f "templates/$*.yaml" NAME=$@ PVCNAME=$@-pvc | \
	  kubectl apply -f -
	oc process --local -f "templates/$*.yaml" NAME=$@ PVCNAME=$@-pvc | \
	  kubectl delete -f -

%-generated-name-apply-and-remove:
	oc process --local -f "templates/$*.yaml" PVCNAME=$@-pvc > $@.yaml
	kubectl apply -f $@.yaml
	kubectl delete -f $@.yaml
	rm -v $@.yaml

%-start-and-stop: %.pvc
	oc process --local -f "templates/$*.yaml" NAME=$@ PVCNAME=$* | \
	  kubectl apply -f -
	virtctl start $@
	$(TRAVIS_FOLD_START)
	while ! kubectl get vmi $@ -o yaml | grep "phase: Running" ; do make gather-env-of-$@ ; sleep 3; done
	make gather-env-of-$@
	$(TRAVIS_FOLD_END)
	# Wait for a pretty universal magic word
	virtctl console --timeout=5 $@ | tee /dev/stderr | egrep -m 1 "Welcome|systemd"
	oc process --local -f "templates/$*.yaml" NAME=$@ PVCNAME=$* | \
	  kubectl delete -f -

pvs: $(TESTABLE_GUESTS:%=%.pv)
raws: $(TESTABLE_GUESTS:%=%.raw)

%.pvc: %.pv
	kubectl get pvc $*

# We expect:
# travis: minikube --driver=none -- Then outter==inner path
# local: minikube --driver=kvm2 --mount --mount-string $PWD:/minikube-host
PVPATH=$$PWD/pvs
ifdef TRAVIS
INNERPVPATH=$(PVPATH)
else
INNERPVPATH=/minikube-host/pvs
endif
%.pv: %.raw
	$(TRAVIS_FOLD_START)
	SIZEMB=$$(( $$(qemu-img info $< --output json | jq '.["virtual-size"]') / 1024 / 1024 + 128 )) && \
	mkdir -p "$(PVPATH)/$*" && \
	ln $< $(PVPATH)/$*/disk.img && \
	sudo chown -R 107:107 $(PVPATH) && \
	sudo chmod -R a+Xr $(PVPATH) && \
	bash create-minikube-pvc.sh "$*" "$${SIZEMB}M" "$(INNERPVPATH)/$*/" | tee | kubectl apply -f -
	find $(PVPATH)
	kubectl get -o yaml pv $*
	$(TRAVIS_FOLD_END)

%.raw: %.qcow2
	qemu-img convert -p -O raw $< $@

fedora28.qcow2:
	curl -L -o $@ https://download.fedoraproject.org/pub/fedora/linux/releases/28/Cloud/x86_64/images/Fedora-Cloud-Base-28-1.1.x86_64.qcow2

ubuntu1804.qcow2:
	curl -L -o $@ http://cloud-images.ubuntu.com/bionic/current/bionic-server-cloudimg-amd64.img

opensuse15.qcow2:
	curl -L -o $@ https://download.opensuse.org/repositories/Cloud:/Images:/Leap_15.0/images/openSUSE-Leap-15.0-OpenStack.x86_64-0.0.4-Buildlp150.12.12.qcow2

centos7.qcow2:
	curl -L http://cloud.centos.org/centos/7/images/CentOS-7-x86_64-GenericCloud.qcow2.xz | xz -d > $@

# For now we test the RHEL75 template with the CentOS image
rhel75.raw: centos7.raw
	ln $< $@

clean:
	rm -v *.raw *.qcow2

.PHONY: all test common-templates.yaml
