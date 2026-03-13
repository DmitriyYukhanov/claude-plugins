# LSP Setup Gotchas

Collected from practical installation sessions. Check these when troubleshooting.

## Environment-Specific Issues

### MINGW (Git Bash on Windows)

- **dotnet tools not in PATH:** After `dotnet tool install --global csharp-ls`, the binary lands in `~/.dotnet/tools/` which is not on PATH by default. Add to `~/.bashrc`:
  ```bash
  export PATH="$PATH:$HOME/.dotnet/tools"
  ```
- **nvm4w node path:** npm global binaries install to the nvm4w-managed node directory (e.g., `/c/nvm4w/nodejs/`). Verify with `which <binary>`.

### WSL (Ubuntu)

- **sudo hangs from MINGW:** Running `wsl bash -c 'sudo ...'` from MINGW hangs if the user needs to enter a password. Configure passwordless sudo first:
  ```bash
  sudo visudo
  # Add: username ALL=(ALL) NOPASSWD: ALL
  ```
- **dotnet-sdk-9.0 does not exist on Ubuntu 24.04:** Only `dotnet-sdk-8.0` and `dotnet-sdk-10.0` are available in the default Ubuntu 24.04 repos. Use `sudo apt install -y dotnet-sdk-8.0`.
- **Node 18 engine warnings:** Ubuntu 24.04 ships Node 18 via apt. `typescript-language-server@5.x` requires Node >=20. Install Node 20+ via nodesource or nvm.
- **dotnet tools PATH in WSL:** Same as MINGW — add `$HOME/.dotnet/tools` to PATH in `~/.bashrc`.
- **Windows binaries on WSL PATH:** WSL path interop can expose Windows binaries (e.g., `/mnt/c/nvm4w/nodejs/npm`). These may not work correctly for Linux packages. Prefer native Linux binaries.

### macOS

- **brew required for many servers:** `clangd` (via llvm), `jdtls`, `kotlin-lsp`, `lua-language-server` all install via Homebrew. Ensure brew is installed.
- **Xcode required for Swift:** `sourcekit-lsp` comes with Xcode or the Swift toolchain. No separate install needed.

## Claude Code-Specific Issues

### Plugin vs. Project-Root .lsp.json

- **`.lsp.json` at project root does NOT work.** LSP configuration must come through a marketplace plugin, not a manual `.lsp.json` file at the project root.
- The correct approach: install the official LSP plugin from `claude-plugins-official` marketplace.

### Restart Required

- **`/reload-plugins` is NOT enough for LSP servers.** The reload message explicitly says: "Restart to activate N LSP servers provided by plugins."
- Must do a full `/exit` + relaunch (`claude --resume <session-id>` to continue).

### Plugin Installed but Disabled

- A plugin can be installed but show as disabled. Always verify with `claude plugin list` and run `claude plugin enable <name>` if needed.

### ENABLE_LSP_TOOL Environment Variable

- `ENABLE_LSP_TOOL=1` must be set in `~/.claude/settings.json` under the `"env"` key.
- Also recommended in `~/.bashrc` / `~/.zshrc` for shell-level availability.
- Without this, the LSP tool won't activate even with plugins installed.

## Verification

### Check Debug Logs

After restart, check `~/.claude/debug/latest` for the line:
```
Total LSP servers loaded: N
```
Where N > 0 indicates LSP servers started successfully.

### Test with LSP Tool

Run an LSP operation on a project file to confirm:
```
LSP documentSymbol on <any-source-file>
```

If it returns "No LSP server available for file type: .XX" after restart, the plugin may not be enabled or the binary is not on PATH.

## Binary Verification Commands

Quick checks for each language server:

| Binary | Verify Command |
|--------|---------------|
| `clangd` | `clangd --version` |
| `csharp-ls` | `csharp-ls --version` |
| `gopls` | `gopls version` |
| `jdtls` | `jdtls --version` (or check install dir) |
| `kotlin-lsp` | `kotlin-lsp --version` |
| `lua-language-server` | `lua-language-server --version` |
| `intelephense` | `intelephense --version` |
| `pyright` | `pyright --version` |
| `ruby-lsp` | `ruby-lsp --version` |
| `rust-analyzer` | `rust-analyzer --version` |
| `sourcekit-lsp` | `sourcekit-lsp --version` |
| `typescript-language-server` | `typescript-language-server --version` |
