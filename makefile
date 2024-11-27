SHELL=/bin/bash

# i.e. fedora28.yaml
ALL_META_TEMPLATES=$(wildcard templates/*.yaml)
ALL_PRESETS=$(wildcard presets/*.yaml)
METASOURCES=$(ALL_META_TEMPLATES) $(ALL_PRESETS)

# target architecture
TARGET_ARCH?=x86_64

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

dist/common-templates-amd64.yaml:
	( \
	  echo -n "# Version " ; \
	  git describe --always --tags HEAD ; \
	  for F in $(ALL_PRESETS) dist/templates/*.yaml; \
	  do \
		case "$$F" in \
		  *s390x.yaml) ;; \
		  *) \
	        echo "---" ; \
	        echo "# Source: $$F" ; \
	        cat $$F ; \
		esac ; \
	  done ; \
	) >$@

dist/common-templates-s390x.yaml:
	( \
	  echo -n "# Version " ; \
	  git describe --always --tags HEAD ; \
	  for F in $(ALL_PRESETS) dist/templates/*-s390x.yaml; \
	  do \
	    echo "---" ; \
	    echo "# Source: $$F" ; \
	    cat $$F ; \
	  done ; \
	) >$@

release: dist/common-templates.yaml dist/common-templates-amd64.yaml dist/common-templates-s390x.yaml
	cp dist/common-templates.yaml dist/common-templates-$(VERSION).yaml
	cp dist/common-templates-amd64.yaml dist/common-templates-amd64-$(VERSION).yaml
	cp dist/common-templates-s390x.yaml dist/common-templates-s390x-$(VERSION).yaml

e2e-tests:
	TARGET_ARCH=$(TARGET_ARCH) ./automation/test.sh

go-tests:
	go test -v ./tests/

unit-tests: generate
	./automation/unit-tests.sh

validate-no-offensive-lang:
	./automation/validate-no-offensive-lang.sh

generate: generate-templates.yaml $(METASOURCES)
	# Just build the XML files, no need to export to tarball
	make -C osinfo-db/ OSINFO_DB_EXPORT=echo
	ansible-playbook generate-templates.yaml -e "target_arch=x86_64"
	ansible-playbook generate-templates.yaml -e "target_arch=s390x"

update-osinfo-db:
	git submodule init
	git submodule update --remote osinfo-db

clean:
	rm -rf dist/templates

.PHONY: all generate release e2e-tests unit-tests go-tests
