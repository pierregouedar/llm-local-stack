# Starts (or restarts) the stack:
#   - llama-swap on <listen>:<llama_swap_port>, with an API key (config generated from the template)
#   - opencode serve (optional, if "opencode" is set in config.json) on <listen>:<opencode_port>
#   - the idle-sleep watchdog
# -IfNotRunning     : do nothing if the stack is already running and answering (used by the agent after a wake-up).
# -KeepAwakeHours N : instead of the idle-sleep watchdog, keep the machine awake for N hours.
param([int]$KeepAwakeHours = 0, [switch]$IfNotRunning)

$ErrorActionPreference = 'Continue'
. "$PSScriptRoot\lib.ps1"

if ($IfNotRunning) {
  # After a wake-up the network takes a few seconds to come back: wait up to 60 s before deciding.
  $ip = Get-ListenIp 30
  $up = $false
  if (Get-Process llama-swap -ErrorAction SilentlyContinue) {
    for ($i = 0; $i -lt 30 -and -not $up; $i++) {
      try { $null = Invoke-WebRequest "http://${ip}:$($Cfg.llama_swap_port)/health" -UseBasicParsing -TimeoutSec 2; $up = $true }
      catch { if ($_.Exception.Response) { $up = $true } else { Start-Sleep -Seconds 2 } }
    }
  }
  if ($up) { Log 'stack already running and answering, nothing to do'; return }
  Log 'stack missing or not answering, full restart'
}

# Stop whatever is running (not the agent).
Get-StackProcesses | ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
Start-Sleep -Seconds 2

$ip = Get-ListenIp

# 1) llama-swap (config regenerated on every start)
$yaml = Write-LlamaSwapConfig
Start-Process -FilePath $Cfg.llama_swap -ArgumentList @('--config', "`"$yaml`"", '--listen', "${ip}:$($Cfg.llama_swap_port)") `
  -WorkingDirectory $ServerDir -WindowStyle Hidden `
  -RedirectStandardOutput (Join-Path $Logs 'llama-swap.out.log') -RedirectStandardError (Join-Path $Logs 'llama-swap.err.log')
Log "llama-swap started on ${ip}:$($Cfg.llama_swap_port)"

# 2) opencode serve (optional: drive projects that live on this machine with "opencode attach")
if ($Cfg.opencode) {
  $env:OPENCODE_SERVER_PASSWORD = Get-Secret 'opencode-password.txt'
  if ($Cfg.extra_path) { $env:PATH = "$($Cfg.extra_path);$env:PATH" }
  Start-Process -FilePath $Cfg.opencode -ArgumentList @('serve', '--hostname', $ip, '--port', $Cfg.opencode_port) `
    -WorkingDirectory $env:USERPROFILE -WindowStyle Hidden `
    -RedirectStandardOutput (Join-Path $Logs 'opencode.out.log') -RedirectStandardError (Join-Path $Logs 'opencode.err.log')
  Log "opencode serve started on ${ip}:$($Cfg.opencode_port)"
}

# 3) idle-sleep watchdog, or keep awake for a while
if ($KeepAwakeHours -gt 0) {
  Start-Process powershell.exe -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-WindowStyle', 'Hidden', '-File', "`"$PSScriptRoot\keep-awake.ps1`"", '-Hours', $KeepAwakeHours) -WindowStyle Hidden
  Log "keeping the machine awake for $KeepAwakeHours h"
} elseif ([int]$Cfg.idle_sleep_minutes -le 0) {
  Log 'idle sleep disabled (idle_sleep_minutes = 0)'
} else {
  Start-Process powershell.exe -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-WindowStyle', 'Hidden', '-File', "`"$PSScriptRoot\idle-sleep.ps1`"") -WindowStyle Hidden
  Log "idle-sleep watchdog started ($($Cfg.idle_sleep_minutes) min)"
}
