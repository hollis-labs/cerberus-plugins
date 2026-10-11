// Dropped into cerberus's internal/pluginhost by scripts/loadcheck.sh and run
// there: internal/ packages cannot be imported from another module, so this
// file is the only way to drive the real host. It is not part of any module in
// this repo (no go.mod in this directory), so go vet/test here never see it.
//
// It installs one built plugin bundle (LOADCHECK_BUNDLE) into a fresh manager
// and runs the host's own Install, Load and Health. Load is the assertion: a
// protocol or contract mismatch fails there as `invalid_init`. An unhealthy
// Health because a credential or tool is missing is expected and passes. No
// plugin operation is executed.
package pluginhost

import (
	"context"
	"os"
	"path/filepath"
	"testing"
	"time"
)

func TestLoadCheck(t *testing.T) {
	bundle := os.Getenv("LOADCHECK_BUNDLE")
	if bundle == "" {
		t.Skip("LOADCHECK_BUNDLE not set")
	}

	// Nothing from the real environment reaches the plugin: a throwaway HOME
	// and XDG tree, and no tokens.
	home := t.TempDir()
	env := []string{
		"HOME=" + home,
		"XDG_CONFIG_HOME=" + filepath.Join(home, ".config"),
		"XDG_DATA_HOME=" + filepath.Join(home, ".local", "share"),
		"XDG_CACHE_HOME=" + filepath.Join(home, ".cache"),
		"XDG_STATE_HOME=" + filepath.Join(home, ".local", "state"),
		"PATH=" + os.Getenv("PATH"),
	}
	root := t.TempDir()
	m := NewManager(
		DirectoryInstaller{Policy: LocalInstallPolicy()},
		SubprocessLauncher{Transport: StdioTransportFactory{}, Env: env},
		"loadcheck",
		WithRuntimeRoots(filepath.Join(root, "data"), filepath.Join(root, "cache")),
	)

	ctx, cancel := context.WithTimeout(context.Background(), 60*time.Second)
	defer cancel()

	installed, err := m.Install(ctx, bundle)
	if err != nil {
		t.Fatalf("install: %v", err)
	}
	if err := m.Load(ctx, installed.ID); err != nil {
		t.Fatalf("LOAD FAILED for %s: %v", installed.ID, err)
	}
	defer func() { _ = m.Unload(context.Background(), installed.ID) }()

	h, err := m.Health(ctx, installed.ID)
	if err != nil {
		t.Fatalf("health call failed for %s: %v", installed.ID, err)
	}
	if !h.Loaded {
		t.Fatalf("%s loaded but Health reports not loaded: %s", installed.ID, h.Message)
	}
	t.Logf("loaded %s %s: healthy=%v message=%q", installed.ID, installed.Version, h.Healthy, h.Message)
}
