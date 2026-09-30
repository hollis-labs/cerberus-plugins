# Shared entry points for every plugin in this repo. Each plugin is its own Go
# module under its own directory, so these targets iterate over the list rather
# than recursing into a single build.
#
# Adding a plugin means adding its directory name here and nothing else.

PLUGINS := contextforge azure kubernetes cloudflare digitalocean namecheap forge keeper onepassword github vercel

.PHONY: all test lint dist release-bundle clean

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
dist:
	@for p in $(PLUGINS); do \
		echo "==> dist $$p"; \
		(cd $$p && $(MAKE) dist) || exit 1; \
	done

# release/<plugin>-<version>/ holds that plugin's release tarballs, one per
# platform, and SHA256SUMS: what pushing the <plugin>/v<version> tag publishes.
# Useful to check a release before tagging. It never touches dist/.
#   make release-bundle PLUGIN=kubernetes VERSION=0.3.0
release-bundle:
	@test -n "$(PLUGIN)" -a -n "$(VERSION)" || { echo "usage: make release-bundle PLUGIN=<id> VERSION=X.Y.Z"; exit 2; }
	scripts/release-bundle.sh $(PLUGIN) $(VERSION)

clean:
	rm -rf dist
