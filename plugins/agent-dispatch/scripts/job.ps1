# agent-dispatch's Windows launcher: job.ps1 <bash.exe> <script>. Runs the bash script inside a
# job object that dies with this process, so stopping this one process stops every process the
# run started, however deep, including Git Bash grandchildren whose parent already exited
# (taskkill /T misses those). Only two paths come in: PowerShell 5.1 mangles quoted arguments.
# Before bash starts, this process writes its own pid to `run` next to the script (the tick's
# lock), so the tick can stop the run from the moment the CLI can exist. The pid goes to run.tmp
# first and is renamed into place, so a reader sees no file or the whole number, never half of it.
# ErrorActionPreference=Stop makes every failure in the first block terminating: nothing there
# can fall through to running bash outside the job object. That block exits 96, which the tick
# reads as "the launcher could not start the run"; the catch writes to the console directly,
# since Write-Error under Stop would itself throw and exit 1 instead.
$ErrorActionPreference = 'Stop'
try {
  Add-Type @'
using System;
using System.Runtime.InteropServices;
public static class AgentDispatchJob {
  [DllImport("kernel32.dll", SetLastError = true)] static extern IntPtr CreateJobObject(IntPtr a, string n);
  [DllImport("kernel32.dll", SetLastError = true)] static extern bool SetInformationJobObject(IntPtr j, int c, byte[] i, int l);
  [DllImport("kernel32.dll", SetLastError = true)] static extern bool AssignProcessToJobObject(IntPtr j, IntPtr p);
  [DllImport("kernel32.dll")] static extern IntPtr GetCurrentProcess();
  public static void Enter() {
    IntPtr job = CreateJobObject(IntPtr.Zero, null);
    // JOBOBJECT_EXTENDED_LIMIT_INFORMATION; LimitFlags sits at offset 16 on 32- and 64-bit alike.
    byte[] info = new byte[IntPtr.Size == 8 ? 144 : 112];
    BitConverter.GetBytes(0x2000).CopyTo(info, 16); // JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE
    if (job == IntPtr.Zero || !SetInformationJobObject(job, 9, info, info.Length) ||
        !AssignProcessToJobObject(job, GetCurrentProcess()))
      throw new Exception("agent-dispatch: no job object (error " + Marshal.GetLastWin32Error() + ")");
  }
}
'@
  [AgentDispatchJob]::Enter()
  $run = Join-Path (Split-Path -Parent $args[1]) 'run'
  [IO.File]::WriteAllText("$run.tmp", "$PID`n")
  Move-Item -Force -LiteralPath "$run.tmp" -Destination $run
} catch {
  [Console]::Error.WriteLine("agent-dispatch: $_")
  exit 96
}
try {
  & $args[0] $args[1]
  if ($null -eq $LASTEXITCODE) { exit 1 } # bash never started: `exit $null` would be 0
  exit $LASTEXITCODE
} catch {
  [Console]::Error.WriteLine("agent-dispatch: $_")
  exit 1
}
