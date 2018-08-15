
TEMPLATES=$(wildcard templates/*.yaml)

$(TEMPLATES): %: %.syntax-check

%.syntax-check:
	oc process --local -f "$*" NAME=the-vmname PVCNAME=the-pvcname

.PHONY: $(TEMPLATES)
