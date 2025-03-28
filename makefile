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
	echo -n "# Version " > dist/common-templates.yaml;
	git describe --always --tags HEAD >> dist/common-templates.yaml;
	echo -n "# Version " > dist/common-templates-amd64.yaml;
	git describe --always --tags HEAD >> dist/common-templates-amd64.yaml;
	echo -n "# Version " > dist/common-templates-s390x.yaml;
	git describe --always --tags HEAD >> dist/common-templates-s390x.yaml;
	echo -n "# Version " > dist/common-templates-arm64.yaml;
	git describe --always --tags HEAD >> dist/common-templates-arm64.yaml;
	for file in $(ALL_PRESETS) dist/templates/*.yaml; do \
			if [[ "$$file" == *"s390x.yaml" ]]; then \
					echo "---" >> dist/common-templates-s390x.yaml; \
					echo "# Source: $$file" >> dist/common-templates-s390x.yaml; \
					cat "$$file" >> dist/common-templates-s390x.yaml; \
			elif [[ "$$file" == *"arm64.yaml" ]]; then \
					echo "---" >> dist/common-templates-arm64.yaml; \
					echo "# Source: $$file" >> dist/common-templates-arm64.yaml; \
					cat "$$file" >> dist/common-templates-arm64.yaml; \
			else \
					echo "---" >> dist/common-templates-amd64.yaml; \
					echo "# Source: $$file" >> dist/common-templates-amd64.yaml; \
					cat "$$file" >> dist/common-templates-amd64.yaml; \
			fi; \
			echo "---" >> dist/common-templates.yaml; \
			echo "# Source: $$file" >> dist/common-templates.yaml; \
			cat "$$file" >> dist/common-templates.yaml; \
	done

release: dist/common-templates.yaml
	cp dist/common-templates.yaml dist/common-templates-$(VERSION).yaml
	cp dist/common-templates-amd64.yaml dist/common-templates-amd64-$(VERSION).yaml
	cp dist/common-templates-s390x.yaml dist/common-templates-s390x-$(VERSION).yaml
	cp dist/common-templates-arm64.yaml dist/common-templates-arm64-$(VERSION).yaml

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
	ansible-playbook generate-templates.yaml -e "target_arch=aarch64"

update-osinfo-db:
	git submodule init
	git submodule update --remote osinfo-db

clean:
	rm -rf dist/templates

.PHONY: all generate release e2e-tests unit-tests go-tests
