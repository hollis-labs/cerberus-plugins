# Shared entry points for every plugin in this repo. Each plugin is its own Go
# module under its own directory, so these targets iterate over the list rather
# than recursing into a single build.
#
# A plugin is a top-level directory containing a go.mod. Adding one means
# adding the directory and nothing else: this list, the CI matrix and the load
# check all discover it. Do not hand-maintain a list of plugins anywhere.

PLUGINS := $(sort $(patsubst %/go.mod,%,$(wildcard */go.mod)))

.PHONY: all test lint dist loadcheck release-bundle clean

all: test dist

test:
	@for p in $(PLUGINS); do \
		echo "==> test $$p"; \
		(cd $$p && go test ./...) || exit 1; \
	done

lint:
	@for p in $(PLUGINS); do \
		echo "==> lint $$p"; \
		(cd $$p && go vet ./... && gofmt -l . | (! grep .)) || exit 1; \
	done

# dist/<plugin>/ is an installable plugin directory: plugin.yaml beside bin/.
# Install one with:
#   cerberus connectors plugin managed install dist/<plugin>
# Plugins without a dist target build in place (`make build` writes plugin.yaml
# and bin/ beside the source); scripts/loadcheck.sh handles both layouts.
dist:
	@for p in $(PLUGINS); do \
		echo "==> dist $$p"; \
		if grep -q '^dist:' $$p/Makefile; then t=dist; else t=build; fi; \
		$(MAKE) -C $$p $$t || exit 1; \
	done

# Builds each plugin and loads it into a real Cerberus host (the version the
# plugins pin, from the Go module cache). Fails if any plugin does not load,
# which is how host/plugin protocol skew shows up. No secrets, no vendor APIs.
#   make loadcheck                 every plugin
#   make loadcheck PLUGIN=ufw      one plugin
#   make loadcheck CERBERUS_SRC=~/dev/hollis-labs/apps/cerberus   a local host checkout
loadcheck:
	CERBERUS_SRC="$(CERBERUS_SRC)" scripts/loadcheck.sh $(PLUGIN)

# release/<plugin>-<version>/ holds that plugin's release tarballs, one per
# platform, and SHA256SUMS: what pushing the <plugin>/v<version> tag publishes.
# Useful to check a release before tagging. It never touches dist/.
#   make release-bundle PLUGIN=kubernetes VERSION=0.3.0
release-bundle:
	@test -n "$(PLUGIN)" -a -n "$(VERSION)" || { echo "usage: make release-bundle PLUGIN=<id> VERSION=X.Y.Z"; exit 2; }
	scripts/release-bundle.sh $(PLUGIN) $(VERSION)

clean:
	rm -rf dist
