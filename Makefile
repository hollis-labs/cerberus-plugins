# Shared entry points for every plugin in this repo. Each plugin is its own Go
# module under its own directory, so these targets iterate over the list rather
# than recursing into a single build.
#
# Adding a plugin means adding its directory name here and nothing else.

PLUGINS := contextforge azure kubernetes cloudflare digitalocean

.PHONY: all test lint dist clean

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

clean:
	rm -rf dist
