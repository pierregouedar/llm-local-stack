# Idle-sleep watchdog (Windows):
#  - while the model is computing, keeps Windows from sleeping (without touching power settings);
#  - when the model has done nothing AND nobody has used the machine for idle_sleep_minutes
#    (config.json), puts the machine to sleep (S3). The waker wakes it up again with Wake-on-LAN.
. "$PSScriptRoot\lib.ps1"

$IdleMinutes      = [int]$Cfg.idle_sleep_minutes
$CheckSeconds     = 60
$BusyCpuSecPerMin = 3   # above this, llama-server counts as busy

Add-Type @'
using System;
using System.Runtime.InteropServices;
public static class Pwr {
  [DllImport("kernel32.dll")] public static extern uint SetThreadExecutionState(uint f);
  [StructLayout(LayoutKind.Sequential)] public struct LII { public uint cbSize; public uint dwTime; }
  [DllImport("user32.dll")] static extern bool GetLastInputInfo(ref LII p);
  public static double InputIdleSeconds() {
    LII l = new LII(); l.cbSize = (uint)Marshal.SizeOf(l); GetLastInputInfo(ref l);
    return ((uint)Environment.TickCount - l.dwTime) / 1000.0;
  }
}
'@
Add-Type -AssemblyName System.Windows.Forms
$ES_CONTINUOUS = [uint32]'0x80000000'; $ES_SYSTEM_REQUIRED = [uint32]'0x00000001'

$lastActive = Get-Date
$prevCpu = 0
Log "idle-sleep: sleep after $IdleMinutes min without activity"
while ($true) {
  $cpu = (Get-Process llama-server -ErrorAction SilentlyContinue | Measure-Object CPU -Sum).Sum
  if ($null -eq $cpu) { $cpu = 0 }
  $busy = ($cpu - $prevCpu) -ge $BusyCpuSecPerMin
  $prevCpu = $cpu

  if ($busy) {
    $lastActive = Get-Date
    [void][Pwr]::SetThreadExecutionState($ES_CONTINUOUS -bor $ES_SYSTEM_REQUIRED)
  } else {
    [void][Pwr]::SetThreadExecutionState($ES_CONTINUOUS)
  }

  $modelIdle = ((Get-Date) - $lastActive).TotalMinutes
  $userIdle  = [Pwr]::InputIdleSeconds() / 60
  if ($modelIdle -ge $IdleMinutes -and $userIdle -ge $IdleMinutes) {
    Log ("going to sleep (model idle {0:N0} min, user idle {1:N0} min)" -f $modelIdle, $userIdle)
    [System.Windows.Forms.Application]::SetSuspendState([System.Windows.Forms.PowerState]::Suspend, $false, $false) | Out-Null
    $lastActive = Get-Date
  }
  Start-Sleep -Seconds $CheckSeconds
}
