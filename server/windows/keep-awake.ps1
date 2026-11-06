# Keeps Windows from sleeping for $Hours hours, without changing power settings
# (the effect ends when this script exits).
param([int]$Hours = 12)
Add-Type -Name P -Namespace W -MemberDefinition '[DllImport("kernel32.dll")] public static extern uint SetThreadExecutionState(uint f);'
[void][W.P]::SetThreadExecutionState([uint32]'0x80000001')   # ES_CONTINUOUS | ES_SYSTEM_REQUIRED
Start-Sleep -Seconds ($Hours * 3600)
