# dirty-tree-probe.ps1 -Paths <file>...
# Caller MUST pass each path as a separate quoted argument.
# Emits one JSON object per line; ConvertTo-Json handles backslash and quote escaping.
param([Parameter(Mandatory, ValueFromRemainingArguments)] [string[]] $Paths)
foreach ($p in $Paths) {
  $abs = (Resolve-Path -LiteralPath $p -ErrorAction SilentlyContinue).Path
  if (-not $abs) { $abs = [System.IO.Path]::GetFullPath($p) }
  if (-not (Test-Path -LiteralPath $abs)) {
    [pscustomobject]@{ path=$abs; exists=$false; dirty=$false; untracked=$false; wouldCreate=$true } | ConvertTo-Json -Compress
    continue
  }
  git diff --quiet HEAD -- $abs; $diffhead = ($LASTEXITCODE -ne 0)
  git diff --cached --quiet -- $abs; $staged = ($LASTEXITCODE -ne 0)
  $porcelain = git status --porcelain -- $abs 2>$null
  $untracked = [bool] ($porcelain | Select-String -Pattern '^\?\? ')
  $dirty = ($diffhead -or $staged)
  [pscustomobject]@{ path=$abs; exists=$true; dirty=$dirty; untracked=$untracked; wouldCreate=$false } | ConvertTo-Json -Compress
}
