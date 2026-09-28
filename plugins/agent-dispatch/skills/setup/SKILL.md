---
name: setup
description: >-
  Set up agent-dispatch on this machine: check what a tick needs, then print the repo list,
  labels, saved search and scheduler entry for the owner to install. Use when the user wants
  GitHub labels to start issue-to-pr runs on their machine, or asks why the dispatcher is not
  picking issues up. Prints commands; never runs one that changes anything.
---

# setup: label an issue, get a run

**Never run a command here that changes the machine or GitHub.** Read, check, print; the owner
runs what you print. Resolve `S/` to `../../scripts/` relative to this `SKILL.md`, as an
absolute path.

## 1. Checks

1. Bash, git and `gh`: run the `issue-to-pr:setup` checks (select that skill). Its result stands;
   do not repeat it here.
2. `~/.agent-dispatch/repos.conf`. Missing → print a sample and say where it goes:

   ```
   # <main checkout, absolute path> | claude|codex | trivial|standard|complex|none
   /home/you/code/my-app | claude | trivial
   C:\Users\you\code\my-app | codex | standard
   ```

   The third field is the `--auto-merge` threshold: work at or under it merges without asking.
   For each line: the path is a git checkout (`git -C <path> rev-parse --show-toplevel` prints
   that path) and `gh repo view --json nameWithOwner` in it names a GitHub repo.
3. `agent-dispatch` itself, on the host you are running in now: `tick.sh` refuses to run at all
   when it cannot tell which install is active, so exactly one has to be true here. In Claude
   Code, `~/.claude/plugins/installed_plugins.json` must register `agent-dispatch` in exactly
   one scope (project or user), not both. In Codex, exactly one version may be cached under
   `~/.codex/plugins/cache/*/agent-dispatch/`. Two hits in either place is a blocker: tell the
   owner to uninstall the extra copy and keep exactly one install per host.
4. For every host `repos.conf` names:
   - `claude`: `claude -p "Reply with ok." < /dev/null` prints ok (logged in); `claude plugin list`
     shows issue-to-pr at 9.4.0 or newer.
   - `codex`: `codex login status` says logged in; the only directory under
     `~/.codex/plugins/cache/*/issue-to-pr/` is 9.4.0 or newer.
   A logged-out host or an older issue-to-pr is a blocker: print the fix (`/login`,
   `codex login`, `/plugin update issue-to-pr`, `codex plugin marketplace upgrade`).
5. Windows only: `command -v pwsh`. A path under `WindowsApps` is the Store build, whose child
   processes escape the job object that lets a tick stop a run, and Codex runs its commands
   through `pwsh`. Warn and print `winget install Microsoft.PowerShell`. Also resolve
   `bash.exe`: run `git --exec-path`, which prints `<git root>/mingw64/libexec/git-core` from the
   real install even when `git` on PATH is a scoop shim; drop the last three path parts and add
   `bin/bash.exe`. That is what fills `<bash.exe path>` below. Do not guess
   `$env:ProgramFiles\Git\bin\bash.exe`; that path only holds for a machine-wide install.

## 2. What to print

**Labels**, once per repo:

```
gh label create agent -R <owner/repo> -f -c 1d76db -d "Queued for an agent run"
gh label create agent:running -R <owner/repo> -f -c fbca04 -d "An agent run is working on it"
gh label create agent:waiting -R <owner/repo> -f -c d93f0b -d "The agent asked a question"
gh label create agent:review -R <owner/repo> -f -c 0e8a16 -d "A PR waits for your merge"
gh label create agent:failed -R <owner/repo> -f -c b60205 -d "The run failed; see the last comment"
```

**Saved search**, to bookmark on GitHub web or mobile (GitHub does not notify you of your own
comments, and every comment here is yours):
`is:issue label:agent:waiting,agent:review,agent:failed repo:<owner/repo>` (one `repo:` per line
of `repos.conf`).

**The tick.** Copy the shim once; it finds the current install on every call:

```
mkdir -p ~/.agent-dispatch && cp "S/tick.sh" ~/.agent-dispatch/tick.sh
```

`<host>` below is the host you are running in now (`claude` or `codex`): the tick reads that
host's install record.

**Scheduler**, for the current OS only. Every `<...>` placeholder below (`<host>`, `<home>`,
`<bash.exe path>`, the PATH list) stands for a real value on this machine; fill each one in before
you print it. launchd, systemd and the Windows script all read a literal `<...>` as text, not
something they resolve for you, and a literal `<...>` left in the plist is invalid XML that
`launchctl bootstrap` will refuse.

- Windows, in PowerShell (Git for Windows' `bash.exe`, resolved in check 5 above; a bare `bash` is
  the WSL launcher). Wrapping bash in `conhost.exe --headless` is what keeps the scheduled run
  from flashing a console window open every three minutes:

  ```powershell
  $bash = "<bash.exe path>"
  $tick = "$HOME\.agent-dispatch\tick.sh"
  $a = New-ScheduledTaskAction -Execute 'conhost.exe' -Argument "--headless `"$bash`" `"$tick`" <host>"
  $t = New-ScheduledTaskTrigger -Once -At (Get-Date) -RepetitionInterval (New-TimeSpan -Minutes 3)
  $s = New-ScheduledTaskSettingsSet -MultipleInstances IgnoreNew -ExecutionTimeLimit ([TimeSpan]::Zero) `
    -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable
  Register-ScheduledTask -TaskName agent-dispatch -Action $a -Trigger $t -Settings $s
  ```

  It runs only while you are logged on, which is what lets it use your CLI logins. Run a tick now
  with `Start-ScheduledTask agent-dispatch`.
- macOS: `~/Library/LaunchAgents/agent-dispatch.plist` (a LaunchAgent runs in your login
  session, so the Keychain holding the logins is readable). `<home>` below is `$HOME`'s value on
  this machine, written out in full: launchd never expands `~`, so the plist needs the absolute
  path already:

  ```xml
  <?xml version="1.0" encoding="UTF-8"?>
  <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
  <plist version="1.0"><dict>
    <key>Label</key><string>agent-dispatch</string>
    <key>ProgramArguments</key><array>
      <string>/bin/bash</string><string><home>/.agent-dispatch/tick.sh</string><string><host></string>
    </array>
    <key>EnvironmentVariables</key><dict>
      <key>PATH</key><string><the directories of gh, claude and codex>:/usr/bin:/bin</string>
    </dict>
    <key>StartInterval</key><integer>180</integer>
  </dict></plist>
  ```

  Load it with `launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/agent-dispatch.plist`;
  run a tick now with `launchctl kickstart gui/$(id -u)/agent-dispatch`. launchd never starts a
  second copy while one runs.
- Linux: two files under `~/.config/systemd/user/`:

  ```ini
  # agent-dispatch.service
  [Service]
  Type=oneshot
  TimeoutStartSec=infinity
  Environment=PATH=<the directories of gh, claude and codex>:/usr/bin:/bin
  ExecStart=/bin/bash %h/.agent-dispatch/tick.sh <host>

  # agent-dispatch.timer
  [Timer]
  OnBootSec=2min
  OnUnitActiveSec=3min
  [Install]
  WantedBy=timers.target
  ```

  Then `systemctl --user daemon-reload && systemctl --user enable --now agent-dispatch.timer`;
  run a tick now with `systemctl --user start agent-dispatch`. A oneshot unit never runs twice at
  once.

Find the PATH list with `command -v gh`, `command -v claude` and `command -v codex` on this
machine. Run a tick by hand only through the scheduler, as above: it is what keeps two ticks from
overlapping.

## 3. Report

One block: checks passed and failed, then the printed pieces in the order to apply them (config,
labels, tick.sh, scheduler, saved search). Close with how it behaves: label an issue `agent`;
the tick log is `~/.agent-dispatch/logs/tick.log`, each run's log sits next to it; a CLI error
creates `~/.agent-dispatch/paused`, and dispatching resumes once the owner deletes that file.
Disabling or uninstalling the plugin does not stop the scheduled tick: to stop dispatching, delete
the scheduler entry or create `~/.agent-dispatch/paused`.
