---
name: setup
description: >-
  Set up agent-dispatch on this machine: check what a tick needs, ask each repo's auto-merge
  threshold, then show one summary of the repo list, labels, tick copy and scheduler entry and,
  once the owner confirms, apply all of it. Use when the user wants GitHub labels to start
  issue-to-pr runs on their machine, or asks why the dispatcher is not picking issues up.
---

# setup: label an issue, get a run

**Change nothing until the owner confirms the one summary in step 5; then apply all of it.** The
checks and questions before it only read. Resolve `S/` to `../../scripts/` relative to this
`SKILL.md`, as an absolute path.

## 1. Checks

Any blocker below stops setup here: show its fix, say nothing changed, and have the owner run
setup again once it is fixed.

1. Bash, git and `gh`: run the `issue-to-pr:setup` checks (select that skill). Its result stands;
   do not repeat it here.
2. `~/.agent-dispatch/repos.conf`, one repo per line:

   ```
   # <main checkout, absolute path> | claude|codex | trivial|standard|complex|none
   /home/you/code/my-app | claude | trivial
   C:\Users\you\code\my-app | codex | standard
   ```

   Missing is fine: step 5 creates it. For each existing line: the path is a git checkout
   (`git -C <path> rev-parse --show-toplevel` prints that path; `C:\x` and `C:/x` are the same
   one, so compare them as directories, not strings) and `gh repo view --json nameWithOwner` in
   it names a GitHub repo. A line that fails is a blocker: one bad line stops
   every tick, for every repo. Setup never edits an existing line.
3. `agent-dispatch` itself, on the host you are running in now: `tick.sh` refuses to run at all
   when it cannot tell which install is active, so exactly one has to be true here. In Claude
   Code, `~/.claude/plugins/installed_plugins.json` must register `agent-dispatch` in exactly
   one scope (project or user), not both. In Codex, exactly one version may be cached under
   `~/.codex/plugins/cache/*/agent-dispatch/`, and its `[plugins."agent-dispatch@…"]` section in
   `~/.codex/config.toml` must say `enabled = true`. Two hits, or a disabled plugin, in either
   place is a blocker: tell the owner to uninstall the extra copy, or enable the plugin, so one
   install is active per host.
4. Windows only: `command -v pwsh`. A path under `WindowsApps` is the Store build: a Store `pwsh`
   started inside a run survives the job object that lets a tick stop the run, and Codex runs its
   commands through `pwsh`. Not a blocker: unless the machine PATH
   (`[Environment]::GetEnvironmentVariable('Path','Machine')`) already lists
   `PowerShell\7`, step 5 offers the machine-wide MSI build:
   `winget install --id Microsoft.PowerShell -e --source winget --installer-type wix --scope machine
   --accept-source-agreements --accept-package-agreements` (the last two answer the prompts a
   first `winget` run shows, which nobody can answer here).
   The Store package can stay: the machine PATH comes before the user PATH that holds
   `WindowsApps`, so once it lists the MSI build, that build wins. Also resolve
   `bash.exe`: run `git --exec-path`, which prints `<git root>/mingw64/libexec/git-core` from the
   real install even when `git` on PATH is a scoop shim; drop the last three path parts and add
   `bin/bash.exe`. That is what fills `<bash.exe path>` below. Do not guess
   `$env:ProgramFiles\Git\bin\bash.exe`; that path only holds for a machine-wide install.

## 2. Repos

Ask which repos a label should dispatch: their main checkouts, as absolute paths. Offer the
current repo's main checkout (the first `worktree` line of `git worktree list --porcelain`, not a
linked worktree, which a finished run deletes) if it names a GitHub repo. Check each path as in
check 2; a repo that `repos.conf` already lists (same `nameWithOwner`) keeps its line and is not
asked about again. The host for a new line is the one you are running in now.

## 3. Auto-merge threshold

One plain question per new repo, with no default: the third field of its `repos.conf` line, the
`--auto-merge` value every run in that repo gets. A repo with no answer gets no line, so nothing is
dispatched for it. Say what the answer means:

- Each run sorts itself into a tier: `trivial` is a short copy or config change on one path,
  `complex` is new behavior, several checklist items or paths, or a `design`, `ux` or `breaking`
  label, and `standard` is everything else.
- A PR merges without the owner only when all of these hold: its tier is at or under the
  threshold (`trivial` < `standard` < `complex`; `none` never merges alone), the run asked the
  owner nothing, the issue never stopped on an earlier run, the reviews came back clean, and the
  diff touches nothing under `human_paths` in the repo's `.claude/issue-to-pr/config.md`.
  Everything else waits at `agent:review` for the owner's `merge` reply.
- A self-merge lands on the base branch like any merge. Where a push there publishes a release or
  deploys, a self-merge is a release; a headless run also runs the config's `after_merge`, usually
  a deploy, after it merges.

Read that checkout's `.claude/issue-to-pr/config.md` and name what its `human_paths` and
`after_merge` say for this repo, or that it sets neither.

## 4. Hosts

For every host the finished list names (existing lines and new ones):

- `claude`: `claude -p "Reply with ok." < /dev/null` prints ok (logged in); `claude plugin list`
  shows issue-to-pr at 9.4.0 or newer.
- `codex`: `codex login status` says logged in; the only directory under
  `~/.codex/plugins/cache/*/issue-to-pr/` is 9.4.0 or newer.

A logged-out host or an older issue-to-pr is a blocker, as in step 1: show the fix (`/login`,
`codex login`, `/plugin update issue-to-pr`, `codex plugin marketplace upgrade`) and stop.

## 5. Confirm and apply

Show one summary of everything setup is about to change, in the order it will run, each item as
the exact command or file content with every `<...>` filled in (below), and each marked *new*,
*replaces* or *unchanged*:

1. Windows, Store `pwsh` only: the `winget` command from check 4. It shows a UAC prompt the owner
   has to accept.
2. The five labels for every repo in the list, existing lines included.
3. The lines to append to `repos.conf`, one per new repo, each with its threshold.
4. The `tick.sh` copy.
5. The scheduler entry for this OS. It is *unchanged*, and not run, only when it is both in place
   and live: on Windows `Get-ScheduledTask agent-dispatch` exists, its `State` is not `Disabled`,
   and its action runs this `$bash`, `$tick` and `<host>`; on macOS the plist holds exactly this
   content and `launchctl print gui/$(id -u)/agent-dispatch` finds the job; on Linux the unit
   files hold exactly this content and `systemctl --user is-enabled agent-dispatch.timer` and
   `is-active` both succeed.
   On macOS, replacing a loaded job while `~/.agent-dispatch/lock/` exists stops the run in
   progress: the bootout below ends the tick, and the next tick stops its run and marks the issue
   failed. Say so on this item.

Then ask once: **Apply all of this?** A reply that corrects an item (another host, which the Hosts
step then checks, another threshold, or leaving out the `winget` install) updates the summary and
asks again. `no` changes nothing. `yes` runs the items in that order. The labels come before
`repos.conf` because a listed repo is dispatched on the next tick, and a run cannot label an issue
with a label the repo lacks. The scheduler goes last because it fires a tick at once, and a tick
with no `repos.conf` dies. Stop at the first failure and roll nothing back: every item is safe to
run twice, so running setup again is the recovery.

Give `winget` the longest timeout the host allows: it waits on the owner's UAC click. Judge it by
the machine PATH, not its exit code (a reboot request or an already installed package exits
nonzero too): read the PATH again with the `[Environment]` call from check 4; it must list
`PowerShell\7`. This shell's own PATH was read before the install and proves nothing.

**`repos.conf`**: create `~/.agent-dispatch/` if missing and append the new lines, adding a newline
first when the file does not end with one; a line glued onto the one before it is a malformed line.

**Labels**, once per repo (`-f` updates a label that already exists):

```
gh label create agent -R <owner/repo> -f -c 1d76db -d "Queued for an agent run"
gh label create agent:running -R <owner/repo> -f -c fbca04 -d "An agent run is working on it"
gh label create agent:waiting -R <owner/repo> -f -c d93f0b -d "The agent asked a question"
gh label create agent:review -R <owner/repo> -f -c 0e8a16 -d "A PR waits for your merge"
gh label create agent:failed -R <owner/repo> -f -c b60205 -d "The run failed; see the last comment"
```

**The tick.** Copy the shim; it finds the current install on every call:

```
mkdir -p ~/.agent-dispatch && cp "S/tick.sh" ~/.agent-dispatch/tick.sh
```

`<host>` below is the host you are running in now (`claude` or `codex`): the tick reads that
host's install record.

**Scheduler**, for the current OS only. Every `<...>` placeholder below (`<host>`, `<home>`,
`<bash.exe path>`, the PATH list) stands for a real value on this machine; fill each one in before
you show it. launchd, systemd and the Windows script all read a literal `<...>` as text, not
something they resolve for you, and a literal `<...>` left in the plist is invalid XML that
`launchctl bootstrap` will refuse.

- Windows, in PowerShell (Git for Windows' `bash.exe`, resolved in check 4 above; a bare `bash` is
  the WSL launcher). Wrapping bash in `conhost.exe --headless` is what keeps the scheduled run
  from flashing a console window open every three minutes; `-Force` replaces the task a
  previous setup registered:

  ```powershell
  $bash = "<bash.exe path>"
  $tick = "$HOME\.agent-dispatch\tick.sh"
  $a = New-ScheduledTaskAction -Execute 'conhost.exe' -Argument "--headless `"$bash`" `"$tick`" <host>"
  $t = New-ScheduledTaskTrigger -Once -At (Get-Date) -RepetitionInterval (New-TimeSpan -Minutes 3)
  $s = New-ScheduledTaskSettingsSet -MultipleInstances IgnoreNew -ExecutionTimeLimit ([TimeSpan]::Zero) `
    -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable
  Register-ScheduledTask -TaskName agent-dispatch -Action $a -Trigger $t -Settings $s -Force
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

  Load it with `launchctl bootout gui/$(id -u)/agent-dispatch 2>/dev/null; launchctl bootstrap
  gui/$(id -u) ~/Library/LaunchAgents/agent-dispatch.plist`. The bootout unloads what a previous
  setup loaded, since bootstrap refuses a loaded job; its error when nothing was loaded is
  expected. A bootstrap that fails with `5: Input/output error` ran before the unload finished:
  wait a second and retry it once. Run a tick now with `launchctl kickstart
  gui/$(id -u)/agent-dispatch`. launchd never starts a second copy while one runs.
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

## 6. Report

One block: the checks, then each summary item as applied, failed (with its error) or not reached;
after `no`, one line saying nothing changed. Then one line per repo, `<owner/repo> | <host> |
<threshold>`, and the saved search to bookmark on GitHub web or mobile, since GitHub does not
notify you of your own comments and every comment here is yours:
`is:issue label:agent:waiting,agent:review,agent:failed repo:<owner/repo>` (one `repo:` per line
of `repos.conf`). Close with how it behaves: label an issue `agent`;
the tick log is `~/.agent-dispatch/logs/tick.log`, each run's log sits next to it; a CLI error
creates `~/.agent-dispatch/paused`, and dispatching resumes once the owner deletes that file.
Disabling or uninstalling the plugin does not stop the scheduled tick: to stop dispatching, delete
the scheduler entry or create `~/.agent-dispatch/paused`.
