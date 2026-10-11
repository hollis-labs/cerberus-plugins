# Migrating a plugin to protocol 2

Cerberus `02ac61b` ("adopt published monorepo packages and protocol 2") moved the
host to `github.com/hollis-labs/libs/plugin-mcp`. A plugin built on
`github.com/hollis-labs/plugin-sdk` (protocol 1) is refused at load with
`subprocess init: invalid_init (result)`. `cloudflare/` is the reference
migration; this is the mechanical recipe.

## Versions

- `github.com/hollis-labs/libs/plugin-mcp v0.1.1`: the version the host's
  `go.mod` pins (v0.2.0 also exists and only adds opt-in GrantSet renewal).
- `github.com/hollis-labs/cerberus`: no released tag contains the change
  (`v0.5.0-beta.1` predates it), so pin the pseudo-version of `02ac61b`:
  `v0.5.0-beta.1.0.20261009054531-02ac61b86b4e`. Later main commits do not touch
  `pkg/`. Switch to a tag once one is cut after `02ac61b`.
- `go` directive becomes `1.26.8` (`go get` does this for you).
- No `replace` directives.

## Checklist

1. `go get github.com/hollis-labs/cerberus@02ac61b86b4e github.com/hollis-labs/libs/plugin-mcp@v0.1.1`
2. `sed -i 's#github.com/hollis-labs/plugin-sdk/subprocess#github.com/hollis-labs/libs/plugin-mcp/plugin-sdk/subprocess#'`
   over every `.go` file (main, plugin, tests). Other `plugin-sdk` subpackages
   keep their path under `libs/plugin-mcp/plugin-sdk/`.
3. `go mod edit -droprequire github.com/hollis-labs/plugin-sdk && go mod tidy`.
4. In `Init`, add `CapabilityContract: capability.ContractVersion` to the
   returned `subprocess.InitResult` (import
   `github.com/hollis-labs/libs/plugin-mcp/plugin-sdk/capability`). This is the
   one change that is not an import swap: the host validates the result against
   what it offered, and a zero contract is `invalid_init`.
   `Protocol: subprocess.ProtocolVersion` is now 2 automatically.
5. `main.go`: `subprocess.Serve(plugin)` is unchanged.
6. `plugin.yaml` is unchanged in shape: `protocol: plugin-sdk/subprocess` is still
   the only value `pkg/plugin/plugin_yaml.go` accepts. Run `make dist`.
7. `go vet ./... && go test -race ./...`. Existing tests should need only the
   import swap.

## Init / grants

`InitParams` now carries `CapabilityContract`, `Incarnation` and a `Grants`
array in addition to the old fields. `Grants` is empty unless the host offers
reverse authority; a plugin that only serves operations ignores it. `Config`
(declared secrets keyed by name, `subprocess.NewConfigReader`) is unchanged.
Cerberus's environment capabilities (`ssh_agent`, `docker_socket`) are declared
in `plugin.yaml` and are separate from SDK grants.

## Proving it loads (no live daemon, no ~/.cerberus)

Add a throwaway test (do not commit it) to a cerberus checkout's
`internal/pluginhost`, using `newTestManager`, `DirectoryInstaller{Policy:
LocalInstallPolicy()}` and `SubprocessLauncher{Transport: StdioTransportFactory{},
Env: <HOME and XDG_* in a temp dir, no token>}`; then `Install(distDir)`,
`Load(id)`, `Health(id)` and `ExecuteOperation` for a credential-free-path op
(e.g. `verify_token`). Expect `Load` to succeed with `MissingSecrets` listing the
declared secret, `Health` unhealthy with the plugin's guidance, and the operation
failing with the plugin's missing-credential message, not `invalid_init`.
Running the same test against a protocol-1 build reproduces
`subprocess init: invalid_init (result)`.

## Gotchas

- When every declared secret is optional (tailscale), the proof differs: `Load`
  succeeds, `Health` is healthy with a message saying API operations are
  unavailable, and only the API operation fails per call with the plugin's
  missing-credential error.
- `make build` regenerates `plugin.yaml` in place; for the proof, copy
  `plugin.yaml` and `bin/<plugin>` into a clean bundle directory and install that.

- Run `go mod tidy` before `make dist` so `go.sum` has the new modules.
- The host-side `SessionID` fields on command/MCP requests are no longer
  `omitempty`; plugins using the SDK types are unaffected.
- Do not hand-edit `plugin.yaml`; it is generated from `Definition()`.
