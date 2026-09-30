#!/usr/bin/env bash
# Build one plugin's release bundles: an installable plugin directory
# (plugin.yaml beside bin/, the layout `make dist` writes) per platform, each
# as a tarball, plus SHA256SUMS over them.
#
#   scripts/release-bundle.sh <plugin> <version> [out-dir]
#
# <version> is X.Y.Z, without the leading v. It must equal the version the
# plugin stamps into its own plugin.yaml, so a release named v0.2.0 cannot ship
# a manifest that says 0.1.0. Bump the plugin's Version constant first.
#
# out-dir defaults to release/<plugin>-<version>, never dist/: a host may be
# loading plugins from dist/ right now.
set -euo pipefail

PLATFORMS=(darwin/arm64 darwin/amd64 linux/arm64 linux/amd64)

die() { echo "release-bundle: $*" >&2; exit 1; }

[[ $# -ge 2 ]] || die "usage: $0 <plugin> <version> [out-dir]"
plugin=$1
version=$2
root=$(cd "$(dirname "$0")/.." && pwd)
out=${3:-$root/release/$plugin-$version}

[[ $version =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || die "version $version is not X.Y.Z"

# The plugin must be one the root Makefile builds; that list is the registry.
plugins=$(sed -n 's/^PLUGINS[[:space:]]*:=[[:space:]]*//p' "$root/Makefile")
[[ " $plugins " == *" $plugin "* ]] || die "$plugin is not in the Makefile's PLUGINS list"

dir=$root/$plugin
binary=$(sed -n 's/^BINARY[[:space:]]*:=[[:space:]]*//p' "$dir/Makefile")
[[ -n $binary ]] || die "$plugin/Makefile declares no BINARY"

case $out in "$root/dist"|"$root/dist/"*) die "refusing to write under dist/" ;; esac
rm -rf "$out"
mkdir -p "$out"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

echo "==> test $plugin"
(cd "$dir" && go test ./...)

# plugin.yaml does not depend on the platform, so generate it once with a
# native build. write-dist validates it against the directory it writes into.
echo "==> manifest $plugin"
native=$work/native
mkdir -p "$native/bin"
(cd "$dir" && CGO_ENABLED=0 go build -trimpath -o "$native/bin/$binary" "./cmd/$binary")
"$native/bin/$binary" write-dist "$native"
manifest_version=$(sed -n 's/^version:[[:space:]]*//p' "$native/plugin.yaml" | tr -d "\"'")
[[ $manifest_version == "$version" ]] ||
	die "$plugin's plugin.yaml says version $manifest_version, not $version; bump its Version constant or tag $plugin/v$manifest_version"

for platform in "${PLATFORMS[@]}"; do
	goos=${platform%/*}
	goarch=${platform#*/}
	name=$plugin-$version-$goos-$goarch
	stage=$work/$name/$plugin
	echo "==> build $name"
	mkdir -p "$stage/bin"
	(cd "$dir" && CGO_ENABLED=0 GOOS=$goos GOARCH=$goarch \
		go build -trimpath -ldflags="-s -w" -o "$stage/bin/$binary" "./cmd/$binary")
	cp "$native/plugin.yaml" "$stage/plugin.yaml"
	# The tarball extracts to <plugin>/, ready for `managed install <plugin>`.
	tar -C "$work/$name" -czf "$out/$name.tar.gz" "$plugin"
done

(cd "$out" && shasum -a 256 ./*.tar.gz | sed 's# \./# #' > SHA256SUMS)
echo "==> bundles in $out"
cat "$out/SHA256SUMS"
