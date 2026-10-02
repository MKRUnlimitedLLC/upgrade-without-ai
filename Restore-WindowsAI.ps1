#Requires -Version 5.1
<#
  Restores the policy values written by Disable-WindowsAI.ps1.
  Does not reinstall Copilot. Reinstall that from the Microsoft Store if you want it back.
#>

$ErrorActionPreference = "Continue"

if ($env:PROCESSOR_ARCHITEW6432 -eq "AMD64") {
    $sysnative = Join-Path $env:WINDIR "Sysnative\WindowsPowerShell\v1.0\powershell.exe"
    if (Test-Path $sysnative) {
        Start-Process -FilePath $sysnative -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`"" -Verb RunAs
        exit 0
    }
}

function Test-Admin {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    $p = New-Object Security.Principal.WindowsPrincipal($id)
    return $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

if (-not (Test-Admin)) {
    $arg = "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`""
    Start-Process -FilePath "powershell.exe" -ArgumentList $arg -Verb RunAs
    exit 0
}

$logDir = Join-Path $env:ProgramData "UpgradeWithoutAI"
New-Item -ItemType Directory -Force -Path $logDir | Out-Null
$log = Join-Path $logDir "restore.log"

function Write-Log {
    param([string]$Message)
    $line = "{0}  {1}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), $Message
    Add-Content -Path $log -Value $line
    Write-Host $Message
}

function Remove-Value {
    param([string]$Path, [string]$Name)
    if (Test-Path $Path) {
        Remove-ItemProperty -Path $Path -Name $Name -ErrorAction SilentlyContinue
        Write-Log ("Removed {0}\{1}" -f $Path, $Name)
    }
}

Write-Log "Restore started."

$aiMachine = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsAI"
$aiUser = "HKCU:\SOFTWARE\Policies\Microsoft\Windows\WindowsAI"
$copilotMachine = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsCopilot"
$copilotUser = "HKCU:\SOFTWARE\Policies\Microsoft\Windows\WindowsCopilot"
$paint = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Paint"
$advanced = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced"

foreach ($name in @("AllowRecallEnablement","DisableAIDataAnalysis","DisableClickToDo","DisableSettingsAgent","RemoveMicrosoftCopilotApp")) {
    Remove-Value $aiMachine $name
}
foreach ($name in @("DisableAIDataAnalysis","DisableClickToDo","RemoveMicrosoftCopilotApp")) {
    Remove-Value $aiUser $name
}
Remove-Value $copilotMachine "TurnOffWindowsCopilot"
Remove-Value $copilotUser "TurnOffWindowsCopilot"
foreach ($name in @("DisableCocreator","DisableGenerativeFill","DisableImageCreator")) {
    Remove-Value $paint $name
}
Remove-Value $advanced "ShowCopilotButton"

try {
    Enable-WindowsOptionalFeature -Online -FeatureName "Recall" -NoRestart -ErrorAction Stop | Out-Null
    Write-Log "Recall optional feature re-enabled. It still will not save snapshots until you opt in."
} catch {
    Write-Log ("Recall feature was not restored: {0}" -f $_.Exception.Message)
}

Write-Log "Policy values removed. Copilot was not reinstalled."
Write-Host ""
Write-Host "Restart Windows. To get Copilot back, install Microsoft Copilot from the Store."
Write-Host "Log: $log"
