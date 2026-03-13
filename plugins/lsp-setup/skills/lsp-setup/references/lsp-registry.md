# LSP Plugin Registry (claude-plugins-official)

Complete mapping of languages to their official Claude Code LSP plugins, required binaries, and install commands.

## Official Plugins

| Language | Plugin Name | Binary | Install Command |
|----------|-------------|--------|-----------------|
| C/C++ | `clangd-lsp` | `clangd` | **macOS:** `brew install llvm` · **Linux:** `sudo apt install clangd` · **MINGW:** install LLVM from [releases](https://github.com/llvm/llvm-project/releases) and add to PATH (or use MSYS2: `pacman -S mingw-w64-x86_64-clang-tools-extra`) |
| C# | `csharp-lsp` | `csharp-ls` | `dotnet tool install --global csharp-ls` (requires .NET SDK) |
| Go | `gopls-lsp` | `gopls` | `go install golang.org/x/tools/gopls@latest` |
| Java | `jdtls-lsp` | `jdtls` | **macOS:** `brew install jdtls` · **Linux:** manual install from eclipse.org |
| Kotlin | `kotlin-lsp` | `kotlin-lsp` | **macOS:** `brew install JetBrains/utils/kotlin-lsp` |
| Lua | `lua-lsp` | `lua-language-server` | **macOS:** `brew install lua-language-server` · **Linux:** GitHub releases |
| PHP | `php-lsp` | `intelephense` | `npm install -g intelephense` |
| Python | `pyright-lsp` | `pyright` | `npm install -g pyright` (or `pip install pyright` / `pipx install pyright`) |
| Ruby | `ruby-lsp` | `ruby-lsp` | `gem install ruby-lsp` |
| Rust | `rust-analyzer-lsp` | `rust-analyzer` | `rustup component add rust-analyzer` |
| Swift | `swift-lsp` | `sourcekit-lsp` | Included with Xcode / Swift toolchain |
| TypeScript/JS | `typescript-lsp` | `typescript-language-server` | `npm install -g typescript-language-server typescript` |

## Auto-Detection File Patterns

Map of file patterns to languages for project scanning:

| Pattern | Language |
|---------|----------|
| `*.cs`, `*.csproj`, `*.sln` | C# |
| `*.c`, `*.h`, `*.cpp`, `*.cc`, `*.cxx`, `*.hpp`, `CMakeLists.txt` | C/C++ |
| `*.go`, `go.mod`, `go.sum` | Go |
| `*.java`, `pom.xml`, `build.gradle`, `build.gradle.kts` | Java |
| `*.kt`, `*.kts` | Kotlin |
| `*.lua` | Lua |
| `*.php`, `composer.json` | PHP |
| `*.py`, `*.pyi`, `requirements.txt`, `pyproject.toml`, `setup.py`, `Pipfile` | Python |
| `*.rb`, `Gemfile`, `Rakefile`, `*.gemspec` | Ruby |
| `*.rs`, `Cargo.toml` | Rust |
| `*.swift`, `Package.swift` | Swift |
| `*.ts`, `*.tsx`, `*.js`, `*.jsx`, `*.mjs`, `*.cjs`, `package.json`, `tsconfig.json` | TypeScript/JS |

## Plugin Install/Enable Sequence

For each language detected:

```
1. claude plugin marketplace update claude-plugins-official
2. claude plugin install <plugin-name>@claude-plugins-official
3. Verify plugin appears in: claude plugin list
4. If status shows disabled: claude plugin enable <plugin-name>
```

After all plugins installed, LSP servers require a **full Claude Code restart** (`/exit` + relaunch) to activate. `/reload-plugins` is NOT sufficient for LSP servers.

## Settings.json Structure

The project `.claude/settings.json` should contain enabled plugins:

```json
{
  "enabledPlugins": {
    "pyright-lsp@claude-plugins-official": true,
    "typescript-lsp@claude-plugins-official": true
  }
}
```

The global `~/.claude/settings.json` must contain:

```json
{
  "env": {
    "ENABLE_LSP_TOOL": "1"
  }
}
```
