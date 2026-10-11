#!/usr/bin/env bash
# Build every plugin and LOAD it into a real Cerberus host. Fails if any plugin
# does not load, which is how host/plugin protocol skew shows up (a protocol-1
# plugin against a protocol-2 host dies with `invalid_init`).
#
#   scripts/loadcheck.sh [plugin ...]     # default: every plugin directory
#
# internal/ packages cannot be imported from another module, so the host half
# runs as a test file (ci/loadcheck/loadcheck_test.go) dropped into a copy of
# the cerberus module at the version the plugins pin. The module comes from the
# Go module cache (go mod download), so there is no git clone and the version
# is exactly the one the plugins compile against.
#
# Needs no secrets and no network beyond the Go module proxy. Per plugin it runs
# Install, Load and Health in a throwaway HOME and nothing else.
#
# Environment:
#   CERBERUS_SRC   use this cerberus checkout instead of the pinned module
#                  (it is copied, never modified)
set -euo pipefail

root=$(cd "$(dirname "$0")/.." && pwd)
cd "$root"

die() { echo "loadcheck: $*" >&2; exit 1; }

# One source of truth for what a plugin is: a top-level directory with a go.mod.
if [[ $# -gt 0 ]]; then
	plugins=("$@")
else
	mapfile -t plugins < <(for f in */go.mod; do echo "${f%/go.mod}"; done)
fi
[[ ${#plugins[@]} -gt 0 ]] || die "no plugin directories found"

work=$(mktemp -d)
trap 'chmod -R u+w "$work" 2>/dev/null; rm -rf "$work"' EXIT

# Pinned cerberus version: the newest one any plugin requires (version order).
if [[ -n ${CERBERUS_SRC:-} ]]; then
	cp -r "$CERBERUS_SRC" "$work/cerberus-src"
else
	pins=$(for p in "${plugins[@]}"; do
		sed -n 's#^[[:space:]]*github.com/hollis-labs/cerberus[[:space:]]\{1,\}\(v[^[:space:]]*\).*#\1#p' "$p/go.mod"
	done | sort -u)
	[[ -n $pins ]] || die "no plugin requires github.com/hollis-labs/cerberus; they are not on protocol 2"
	if [[ $(wc -l <<<"$pins") -gt 1 ]]; then
		echo "loadcheck: warning, plugins pin different cerberus versions:" >&2
		# shellcheck disable=SC2086
		printf '  %s\n' $pins >&2
	fi
	pin=$(sort -V <<<"$pins" | tail -n1)
	echo "==> cerberus host: $pin"
	moddir=$(cd "${plugins[0]}" && go mod download -json "github.com/hollis-labs/cerberus@$pin" | sed -n 's/.*"Dir": *"\(.*\)".*/\1/p')
	[[ -d $moddir ]] || die "could not download cerberus@$pin"
	cp -r "$moddir" "$work/cerberus-src"
fi
chmod -R u+w "$work/cerberus-src"
src=$work/cerberus-src
cp ci/loadcheck/loadcheck_test.go "$src/internal/pluginhost/zz_loadcheck_test.go"

echo "==> compiling host load check"
(cd "$src" && go test -c -o "$work/loadcheck.test" ./internal/pluginhost)

passed=()
failed=()
for p in "${plugins[@]}"; do
	[[ -f $p/go.mod ]] || die "$p is not a plugin directory (no go.mod)"
	echo "==> build $p"
	# The plugin's own target: dist writes ../dist/<p>, build writes in place.
	if grep -q '^dist:' "$p/Makefile"; then
		built=$root/dist/$p
		if ! make -s -C "$p" dist >"$work/$p.build.log" 2>&1; then
			cat "$work/$p.build.log"; failed+=("$p (build)"); continue
		fi
	else
		built=$root/$p
		if ! make -s -C "$p" build >"$work/$p.build.log" 2>&1; then
			cat "$work/$p.build.log"; failed+=("$p (build)"); continue
		fi
	fi

	# A clean bundle: only plugin.yaml and the entrypoint binary. `make build`
	# rewrites plugin.yaml in place and leaves other files around it.
	entry=$(sed -n 's/^[[:space:]]*command:[[:space:]]*//p' "$built/plugin.yaml" | head -n1 | tr -d "\"'")
	[[ -n $entry && -f $built/$entry ]] || { echo "no entrypoint binary $entry in $built"; failed+=("$p (bundle)"); continue; }
	bundle=$work/bundles/$p
	mkdir -p "$bundle/$(dirname "$entry")"
	cp "$built/plugin.yaml" "$bundle/plugin.yaml"
	cp "$built/$entry" "$bundle/$entry"

	echo "==> load $p"
	if (cd "$src/internal/pluginhost" && LOADCHECK_BUNDLE=$bundle "$work/loadcheck.test" -test.run '^TestLoadCheck$' -test.v) >"$work/$p.load.log" 2>&1; then
		grep 'loaded ' "$work/$p.load.log" || true
		passed+=("$p")
	else
		cat "$work/$p.load.log"
		failed+=("$p")
	fi
done

echo
echo "loadcheck: ${#passed[@]} loaded, ${#failed[@]} failed (of ${#plugins[@]})"
for p in "${passed[@]}"; do echo "  ok    $p"; done
for p in "${failed[@]}"; do echo "  FAIL  $p"; done
[[ ${#failed[@]} -eq 0 ]]
