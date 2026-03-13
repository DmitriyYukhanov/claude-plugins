---
name: lsp-setup
description: >
  This skill should be used when the user asks to "set up LSP", "configure LSP",
  "install LSP", "enable LSP", "language server setup", "add LSP to project",
  "configure language server", "set up code intelligence", "validate LSP",
  "check LSP setup", "fix LSP", "LSP not working", or wants to enable or
  troubleshoot LSP-powered navigation (go-to-definition, find-references, hover,
  diagnostics) in Claude Code for a project.
---

# LSP Setup for Claude Code Projects

Set up Language Server Protocol support in Claude Code for the current project. This enables semantic code intelligence: go-to-definition, find-references, hover, document symbols, workspace symbols, diagnostics, and call hierarchy — all at ~50ms instead of 30-60s grep-based navigation.

## State Detection

This skill operates as a state machine. On each invocation, detect the current state and resume from the appropriate step:

1. **No LSP configured** → Start from Step 1 (detect languages)
2. **Binaries missing** → Resume at Step 3 (install binaries)
3. **Plugins not installed** → Resume at Step 4 (install plugins)
4. **Plugins installed but LSP returns "No LSP server available"** → Step 5 (restart needed)
5. **LSP responds with symbols** → Step 6 (validation complete, report success)

To detect state quickly: attempt an `LSP documentSymbol` call on any source file in the project. If it returns results, skip to validation. If "No LSP server available", check whether plugins are installed and binaries are on PATH.

## Step 1: Detect Environment

Determine the current environment by checking `uname -s`:
- `MINGW*` or `MSYS*` → MINGW (Git Bash on Windows)
- `/proc/version` contains "microsoft" → WSL
- `Darwin` → macOS
- Otherwise → Linux

This affects install commands and PATH gotchas. Consult `references/gotchas.md` for environment-specific issues.

## Step 2: Detect Languages

Scan the current project directory for language indicators using Glob. Check for source files (`**/*.py`, `**/*.ts`, `**/*.cs`, etc.) and project markers (`**/pyproject.toml`, `**/tsconfig.json`, `**/Cargo.toml`, etc.).

The complete detection pattern table is in `references/lsp-registry.md` under "Auto-Detection File Patterns" — use that as the authoritative source.

Present detected languages for confirmation. If a detected language has no official Claude Code LSP plugin, inform the user and ask whether to skip it.

Only the 12 languages in `references/lsp-registry.md` have official plugins. If auto-detection finds no supported languages, present the full list and let the user pick.

## Step 3: Install Language Server Binaries

The verify script accepts lowercase identifiers, not registry display names. Map detected languages before invoking:

| Registry Name | Script Identifier |
|---------------|-------------------|
| C# | `csharp` |
| C/C++ | `cpp` |
| TypeScript/JS | `typescript` |

All other languages use their lowercase name (e.g., `python`, `go`, `rust`, `java`, `kotlin`, `lua`, `php`, `ruby`, `swift`).

Run the verify script to check all binaries at once:
```bash
bash ${CLAUDE_PLUGIN_ROOT}/scripts/verify-lsp.sh <lang1> <lang2> ...
```

For any missing binary, look up the install command in `references/lsp-registry.md` and run it. Consult `references/gotchas.md` for environment-specific issues before running install commands.

## Step 4: Configure and Install Plugins

### 4a: Global Settings

Check `~/.claude/settings.json` for the `ENABLE_LSP_TOOL` env var. If missing, add it:

```json
{
  "env": {
    "ENABLE_LSP_TOOL": "1"
  }
}
```

The `settings.json` env block is the primary mechanism. As a supplementary fallback, also add `export ENABLE_LSP_TOOL=1` to `~/.bashrc` or `~/.zshrc` if not already present.

### 4b: Marketplace and Plugin Installation

Verify the official marketplace is configured:
```bash
claude plugin marketplace list
```

If `claude-plugins-official` is not listed, add it. Run `claude plugin marketplace add --help` to see the required arguments, then add the marketplace. Once configured, update to fetch the latest catalog:
```bash
claude plugin marketplace update claude-plugins-official
```

For each language, install the corresponding plugin:
```bash
claude plugin install <plugin-name>@claude-plugins-official
```

Refer to `references/lsp-registry.md` for the language-to-plugin mapping.

### 4c: Enable in Project Settings

Verify each plugin is enabled in the project's `.claude/settings.json`:

```json
{
  "enabledPlugins": {
    "<plugin-name>@claude-plugins-official": true
  }
}
```

### 4d: Verify Plugin Status

Run `claude plugin list` and confirm each LSP plugin shows as enabled. If any show as disabled, run `claude plugin enable <name>`.

## Step 5: Session Restart

**Critical:** LSP servers require a full Claude Code restart to activate. `/reload-plugins` is NOT sufficient — it explicitly says "Restart to activate N LSP servers provided by plugins."

Display this message to the user:

> LSP plugins are installed and configured. A full Claude Code restart is required to activate the LSP servers.
>
> Please run `/exit`, then relaunch Claude Code. After restart, re-invoke this skill (say "validate LSP" or "check LSP setup") to confirm everything works.

If the user provides a session ID, suggest: `claude --resume <session-id>`.

## Step 6: Validate LSP

After restart, validate each language:

1. Find a representative source file for each configured language
2. Run `LSP documentSymbol` on that file
3. If symbols are returned → that language's LSP is working
4. If "No LSP server available" → check binary PATH and plugin status

Also check debug logs:
```bash
grep "LSP servers loaded" ~/.claude/debug/latest
```

Report results per language:

```
| Language   | Binary    | Plugin        | Status  |
|------------|-----------|---------------|---------|
| Python     | pyright   | pyright-lsp   | Working |
| TypeScript | ts-ls     | typescript-lsp| Working |
| C#         | csharp-ls | csharp-lsp    | Failed  |
```

For any failures, consult `references/gotchas.md` and attempt remediation.

## Reference Files

- **`references/lsp-registry.md`** — Complete plugin-to-binary mapping, install commands, auto-detection patterns
- **`references/gotchas.md`** — Environment-specific issues, troubleshooting, binary verification commands
- **`scripts/verify-lsp.sh`** — Automated binary and environment verification for detected languages

## LSP Capabilities After Setup

Once configured, the LSP tool provides these operations on project files:

- `goToDefinition` — Jump to symbol source (~50ms)
- `findReferences` — All usages across the codebase
- `hover` — Type signatures and documentation
- `documentSymbol` — All symbols in a file
- `workspaceSymbol` — Search symbols across the project
- `goToImplementation` — Concrete implementations of interfaces
- `incomingCalls` / `outgoingCalls` — Call hierarchy tracing
- `diagnostics` — Real-time type checking and error detection
