# agent-dispatch's Windows launcher: job.ps1 <bash.exe> <script>. Runs the bash script inside a
# job object that dies with this process, so stopping this one process stops every process the
# run started, however deep, including Git Bash grandchildren whose parent already exited
# (taskkill /T misses those). Only two paths come in: PowerShell 5.1 mangles quoted arguments.
# ErrorActionPreference=Stop, so a failed Add-Type compile (a non-terminating error by default)
# cannot fall through to `& $args[0] $args[1]` running bash outside the job object; the catch
# below is the actual guarantee (a `throw` from Enter() is already terminating either way) and
# always exits non-zero, since `& ...` failing to even start bash leaves $LASTEXITCODE $null,
# and `exit $null` is 0, not a failure.
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
  & $args[0] $args[1]
  if ($null -eq $LASTEXITCODE) { exit 1 }
  exit $LASTEXITCODE
} catch {
  Write-Error $_
  exit 1
}
