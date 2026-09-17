# cerberus-plugins

Connector plugins for [Cerberus](https://github.com/hollis-labs/cerberus).

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
contextforge/          the plugin module
  cmd/<binary>/        entrypoint; also generates plugin.yaml
  internal/cfplugin/   backend, DTOs, connector definition, subprocess handler
dist/<plugin>/         built, installable plugin directory (gitignored)
```

`make test` and `make dist` at the root iterate every plugin listed in
`PLUGINS`. Adding a plugin means adding its directory name there.

## Build and install

```bash
make dist
cerberus connectors plugin managed install "$PWD/dist/contextforge"
cerberus connectors plugin managed load contextforge
cerberus connectors plugin managed exec contextforge get_health
```

Unsigned local installs need no trust flags and record `trust_tier: unsigned`.
Destructive operations still require `--ack`.

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
- **The host passes no config or secrets to a plugin subprocess.**
  `SDKInitParams.Config` is always empty today, and the launch environment is a
  fixed allow-list carrying no credentials. A plugin resolves its own secret
  from the keychain (`go-keyring`, service `cerberus`), which is what
  `contextforge` does.
- **Name the thing that actually failed.** A refused connection on a local
  tunnel port means the tunnel is down, not the remote service. Telling an
  operator "gateway is down" sends them to the wrong host.

## Plugins

| Plugin | Status | Notes |
|---|---|---|
| `contextforge` | read-only operations | Adtran MCP gateway. See `contextforge/README.md`. |
