# wait-for-codex.ps1 -JobId <id> [-IntervalSec 30]
# Exits 0 on done, 1 on failed/cancelled, 2 on 15-min timeout.
param(
  [Parameter(Mandatory)] [string] $JobId,
  [int] $IntervalSec = 30
)
# ErrorActionPreference left default so Write-Error does not terminate.

$Companion = $env:CODEX_COMPANION
if (-not $Companion) {
  $base = Join-Path $env:USERPROFILE '.claude\plugins\cache\openai-codex\codex'
  if (Test-Path $base) {
    $Companion = Get-ChildItem -Path $base -Recurse -Filter codex-companion.mjs -ErrorAction SilentlyContinue |
      Sort-Object FullName | Select-Object -Last 1 -ExpandProperty FullName
  }
}
if (-not $Companion -or -not (Test-Path $Companion)) {
  [Console]::Error.WriteLine("ERROR: codex-companion.mjs not found; set CODEX_COMPANION env var to its absolute path")
  exit 1
}

$deadline = (Get-Date).AddMinutes(15)
$nullStreak = 0
while ((Get-Date) -lt $deadline) {
  $json = node $Companion status $JobId --json 2>$null
  $phase = $null
  try { $phase = ($json | ConvertFrom-Json -ErrorAction Stop).job.phase } catch { $phase = $null }

  switch ($phase) {
    'done'      { "$JobId`: done"; exit 0 }
    'failed'    { [Console]::Error.WriteLine("$JobId`: failed"); exit 1 }
    'cancelled' { [Console]::Error.WriteLine("$JobId`: cancelled"); exit 1 }
    { $_ -in @($null, '') } {
      $nullStreak++
      if ($nullStreak -ge 5) {
        [Console]::Error.WriteLine("WARN: $nullStreak consecutive empty/unparseable phase reads")
      }
    }
    default {
      # Valid non-terminal phase (starting, running, etc.) — reset streak.
      $nullStreak = 0
    }
  }
  Start-Sleep -Seconds $IntervalSec
}
[Console]::Error.WriteLine("$JobId`: timeout after 15min")
exit 2
