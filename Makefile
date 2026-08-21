# Chef Infra Client source build helpers
#
# Inline `.PHONY: <target> ## description` lines appear in `make help`.

PLAYBOOK ?= site.yml
ANSIBLE  ?= ansible-playbook

.DEFAULT_GOAL := help

.PHONY: help ## Show this help
help:
	@awk '/^\.PHONY:.*##/ { \
			line = $$0; \
			sub(/^.*\.PHONY:[ \t]*/, "", line); \
			split(line, parts, /[ \t]+##[ \t]*/); \
			printf "  \033[36m%-14s\033[0m %s\n", parts[1], parts[2] \
		} \
		BEGIN { printf "\nUsage:\n  make \033[36m<target>\033[0m\n\nTargets:\n" }' \
		$(MAKEFILE_LIST)

.PHONY: build ## Bootstrap the VM and build chef-client from source
build:
	$(ANSIBLE) $(PLAYBOOK)

.PHONY: validate ## Confirm chef-client --version succeeds on the build VM
validate:
	$(ANSIBLE) $(PLAYBOOK) --tags validate

.PHONY: package ## Build .debs for Ubuntu 22.04, 24.04, and 26.04 (Docker)
package:
	$(ANSIBLE) $(PLAYBOOK) --tags package

.PHONY: package-22.04 ## Build Ubuntu 22.04 (jammy) .deb only
package-22.04:
	$(ANSIBLE) $(PLAYBOOK) --tags package -e 'chef_package_releases=["22.04"]'

.PHONY: package-24.04 ## Build Ubuntu 24.04 (noble) .deb only
package-24.04:
	$(ANSIBLE) $(PLAYBOOK) --tags package -e 'chef_package_releases=["24.04"]'

.PHONY: package-26.04 ## Build Ubuntu 26.04 (resolute) .deb only
package-26.04:
	$(ANSIBLE) $(PLAYBOOK) --tags package -e 'chef_package_releases=["26.04"]'
