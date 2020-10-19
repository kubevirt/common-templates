SHELL=/bin/bash

# i.e. fedora28.yaml
ALL_META_TEMPLATES=$(wildcard templates/*.yaml)
ALL_PRESETS=$(wildcard presets/*.yaml)
METASOURCES=$(ALL_META_TEMPLATES) $(ALL_PRESETS)

# Make sure the version is defined
export VERSION=$(shell ./version.sh)
export REVISION=$(shell ./revision.sh)

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

e2e-tests:
	./automation/test.sh 

generate: generate-templates.yaml $(METASOURCES)
	# Just build the XML files, no need to export to tarball
	make -C osinfo-db/ OSINFO_DB_EXPORT=echo
	ansible-playbook generate-templates.yaml

.PHONY: all generate release e2e-tests build-builder push-builder
