
TEMPLATES=$(wildcard templates/*.yaml)
GUESTS=$(TEMPLATES:templates/%.yaml=%)

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

.PHONY: all test
