
TEMPLATES=$(wildcard templates/*.yaml)

all: $(TEMPLATES)

$(TEMPLATES): %: %.syntax-check

%.syntax-check:
	oc process --local -f "$*" NAME=the-vmname PVCNAME=the-pvcname

test: all

.PHONY: $(TEMPLATES)
