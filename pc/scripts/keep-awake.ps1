# Empeche la mise en veille automatique de Windows pendant $Hours heures,
# sans modifier les reglages d'alimentation (l'effet s'arrete quand ce script se termine).
param([int]$Hours = 12)
Add-Type -Name P -Namespace W -MemberDefinition '[DllImport("kernel32.dll")] public static extern uint SetThreadExecutionState(uint f);'
[void][W.P]::SetThreadExecutionState([uint32]'0x80000001')   # ES_CONTINUOUS | ES_SYSTEM_REQUIRED
Start-Sleep -Seconds ($Hours * 3600)
