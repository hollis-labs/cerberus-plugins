# cerberus-plugins

Connector plugins for [Cerberus](https://github.com/hollis-labs/cerberus).

> **Pre-release.** Every plugin here is at `0.1.x` and read-only: none
> implements a write, lifecycle or destructive operation yet. They run in
> active internal use, but there are no outside users, no compatibility
> guarantees and no support channel. The plugin authoring contract
> (`pkg/plugin`, `pkg/connector`) is itself pre-release and can change with
> Cerberus. Built in the open: interfaces and behavior can change without
> notice. Each plugin's README carries its own status.

A plugin is a standalone binary the Cerberus host launches as a subprocess. It
declares its operations in a manifest, and the host turns each one into a CLI
command, an HTTP API operation and an MCP tool — the same surface a compiled-in
connector gets, without rebuilding the host.

Plugins live here when they are optional per user, carry a vendor SDK, or ship
on someone else's schedule. The primitives the control plane is built on
(`local`, `ssh`, `docker`, `github`) stay compiled into Cerberus itself. See
`docs/plans/connector-work-packages.md` in the Cerberus repo for the split.

## Layout

One directory per plugin, each its own Go module:

```
contextforge/          a plugin module
  cmd/<binary>/        entrypoint; also generates plugin.yaml
  internal/cfplugin/   backend, DTOs, connector definition, subprocess handler
azure/                 another, same shape
dist/<plugin>/         built, installable plugin directory (gitignored)
```

`make test` and `make dist` at the root iterate every plugin listed in
`PLUGINS`. Adding a plugin means adding its directory name there.

## Build and install

```bash
make dist
cerberus connectors plugin managed install "$PWD/dist/contextforge"
cerberus connectors plugin managed load contextforge
cerberus connectors exec contextforge get_health
```

A local install records `origin: installed`. Cerberus does not sign or vet
plugins, so there are no trust flags. Every destructive operation requires
`--ack`, whatever the manifest declares.

`dist/<plugin>/plugin.yaml` is generated from the connector definition by the
plugin binary itself (`<binary> write-dist <dir>`), so the manifest the host
installs cannot drift from the operations the plugin actually serves.

## Writing a plugin

Cerberus is a private module, so `go env -w GOPRIVATE=github.com/hollis-labs/*`
once and `go get` works for anyone with repository access. No `replace`
directive is needed; add one only for convenience when developing beside a local
Cerberus checkout.

A plugin imports exactly four things from the Cerberus side:

```go
contract   "github.com/hollis-labs/cerberus/pkg/connector"  // Definition, Manifest
           "github.com/hollis-labs/cerberus/pkg/resource"   // resource types
cerbplugin "github.com/hollis-labs/cerberus/pkg/plugin"     // plugin.yaml, tool naming
           "github.com/hollis-labs/plugin-sdk/subprocess"   // the protocol
```

Nothing from `internal/`. If a plugin needs something from there, the authoring
contract is missing a piece — raise it against Cerberus rather than reaching in.

### Things that cost time to discover

- **Return your own DTOs, never a vendor SDK type.** See
  `docs/adr/0003-connector-response-dtos.md`. The DTO is an allow-list, so a
  vendor adding a credential field in a minor release cannot silently widen your
  output. `contextforge/internal/cfplugin/dto.go` is the worked example, and
  `dto_test.go` is the assertion that keeps it honest.
- **The host redacts `/(?i)\bBearer[ \t]+\S+/` on every error path.** An error
  message containing the word "bearer" followed by a word arrives at the
  operator garbled. Word auth guidance around it.
- **Declare your secrets; do not resolve them.** The host resolves every secret
  a plugin's manifest declares under `config.secrets` — through the same
  process-env / `connector-secrets.yaml` / keychain chain a built-in connector
  uses — and passes the values in `SDKInitParams.Config`, keyed by the secret
  name. Read them with `subprocess.NewConfigReader(params.Config).Secret(name)`,
  which also registers the value with the logger's redaction tracker. The launch
  environment is still a fixed allow-list carrying no credentials: env is
  ambient, so a credential there would reach every plugin rather than the one
  that declared it. A missing secret does not fail the load; the operation that
  needed it reports `credential_missing`.
- **Name the thing that actually failed.** A refused connection on a local
  tunnel port means the tunnel is down, not the remote service. Telling an
  operator "gateway is down" sends them to the wrong host.

## Plugins

| Plugin | Status | Notes |
|---|---|---|
| `contextforge` | read-only operations | MCP gateway administration. See `contextforge/README.md`. |
| `azure` | read-only operations | Azure inventory and AI model deployments. See `azure/README.md`. |
| `kubernetes` | reads, plus writes behind `--ack` with server-side dry run | Cluster inspection and administration. See `kubernetes/README.md`. |
| `cloudflare` | reads, plus writes behind `--ack` with a plugin-served dry run | Zones and DNS records. Replaces the connector Cerberus compiled in, under the same id, so it installs only on a host without that built-in. See `cloudflare/README.md`. |
| `digitalocean` | reads, plus writes and power actions behind `--ack`, with a plugin-served dry run | Droplets. Replaces the connector Cerberus compiled in, under the same id, so it installs only on a host without that built-in. See `digitalocean/README.md`. |
| `namecheap` | reads, plus whole-zone DNS and nameserver writes behind `--ack`, with a plugin-served dry run that diffs against the current zone | Domains and DNS. Replaces the connector Cerberus compiled in, under the same id, so it installs only on a host without that built-in. See `namecheap/README.md`. |
| `forge` | server and site reads, plus deployment-script, deploy and site-command writes behind `--ack`, with plugin-served dry runs (the script update diffs against the current script) | Laravel Forge. Replaces the connector Cerberus compiled in, under the same id, so it installs only on a host without that built-in. See `forge/README.md`. |
