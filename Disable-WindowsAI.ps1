#Requires -Version 5.1
<#
  Upgrade without AI
  Turns off documented Windows 11 AI policies and removes the Copilot store app.
  Does not disable Defender, Windows Update, or networking.
#>

$ErrorActionPreference = "Continue"

# A 32-bit host cannot see the 64-bit policy keys or AppX packages. Relaunch.
if ($env:PROCESSOR_ARCHITEW6432 -eq "AMD64") {
    $sysnative = Join-Path $env:WINDIR "Sysnative\WindowsPowerShell\v1.0\powershell.exe"
    if (Test-Path $sysnative) {
        Start-Process -FilePath $sysnative -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`"" -Verb RunAs
        exit 0
    }
}

function Test-Admin {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($id)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

if (-not (Test-Admin)) {
    Start-Process -FilePath "powershell.exe" -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`"" -Verb RunAs
    exit 0
}

$logDir = Join-Path $env:ProgramData "UpgradeWithoutAI"
New-Item -ItemType Directory -Force -Path $logDir | Out-Null
$log = Join-Path $logDir "apply.log"
$stamp = Get-Date -Format "yyyyMMdd-HHmmss"
$failed = New-Object System.Collections.Generic.List[string]

function Write-Log {
    param([string]$Message)
    $line = "{0}  {1}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), $Message
    Add-Content -Path $log -Value $line -Encoding UTF8
    Write-Host $Message
}

Write-Log "Upgrade without AI started."
Write-Log ("Edition {0}; build {1}" -f (Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion").EditionID, [Environment]::OSVersion.Version.Build)

$restoredMarker = Join-Path $logDir "user-restored.marker"
if (Test-Path $restoredMarker) {
    Remove-Item $restoredMarker -Force -ErrorAction SilentlyContinue
    if (Test-Path $restoredMarker) {
        Write-Log "Could not clear user-restored marker. The watcher may stay quiet."
    } else {
        Write-Log "Cleared user-restored marker. The post-update watcher will report drift again."
    }
}

function Export-IfPresent {
    param([string]$Key, [string]$OutFile)
    & reg.exe query $Key 1>$null 2>$null
    if ($LASTEXITCODE -eq 0) {
        & reg.exe export $Key $OutFile /y | Out-Null
        if ($LASTEXITCODE -eq 0) {
            Write-Log ("Backed up {0} to {1}" -f $Key, $OutFile)
            return
        }
    }
    Write-Log ("No existing key to back up: {0}" -f $Key)
}

Export-IfPresent "HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsAI" (Join-Path $logDir "backup-hklm-windowsai-$stamp.reg")
Export-IfPresent "HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsCopilot" (Join-Path $logDir "backup-hklm-copilot-$stamp.reg")
Export-IfPresent "HKCU\SOFTWARE\Policies\Microsoft\Windows\WindowsAI" (Join-Path $logDir "backup-hkcu-windowsai-$stamp.reg")
Export-IfPresent "HKCU\SOFTWARE\Policies\Microsoft\Windows\WindowsCopilot" (Join-Path $logDir "backup-hkcu-copilot-$stamp.reg")
Export-IfPresent "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Paint" (Join-Path $logDir "backup-paint-$stamp.reg")

function Set-Dword {
    param([string]$Path, [string]$Name, [int]$Value)
    if (-not (Test-Path $Path)) {
        New-Item -Path $Path -Force | Out-Null
    }
    New-ItemProperty -Path $Path -Name $Name -PropertyType DWord -Value $Value -Force | Out-Null
    $read = Get-ItemProperty -Path $Path -Name $Name -ErrorAction SilentlyContinue
    if ($null -eq $read -or [int]$read.$Name -ne $Value) {
        $failed.Add("$Path\$Name")
        Write-Log ("FAILED to set {0}\{1}" -f $Path, $Name)
        return
    }
    Write-Log ("Verified {0}\{1} = {2}" -f $Path, $Name, $Value)
}

$aiMachine = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsAI"
$aiUser = "HKCU:\SOFTWARE\Policies\Microsoft\Windows\WindowsAI"
$copilotMachine = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsCopilot"
$copilotUser = "HKCU:\SOFTWARE\Policies\Microsoft\Windows\WindowsCopilot"
$paint = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Paint"
$advanced = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced"

Set-Dword $aiMachine "AllowRecallEnablement" 0
Set-Dword $aiMachine "DisableAIDataAnalysis" 1
Set-Dword $aiMachine "DisableClickToDo" 1
Set-Dword $aiMachine "DisableSettingsAgent" 1
Set-Dword $aiMachine "RemoveMicrosoftCopilotApp" 1
Set-Dword $aiUser "DisableAIDataAnalysis" 1
Set-Dword $aiUser "DisableClickToDo" 1
Set-Dword $aiUser "RemoveMicrosoftCopilotApp" 1
Set-Dword $copilotMachine "TurnOffWindowsCopilot" 1
Set-Dword $copilotUser "TurnOffWindowsCopilot" 1
Set-Dword $paint "DisableCocreator" 1
Set-Dword $paint "DisableGenerativeFill" 1
Set-Dword $paint "DisableImageCreator" 1
Set-Dword $advanced "ShowCopilotButton" 0

Write-Log "Removing Recall optional feature if this PC has it."
try {
    $feature = Get-WindowsOptionalFeature -Online -FeatureName "Recall" -ErrorAction Stop
    if ($feature.State -eq "Disabled") {
        Write-Log "Recall optional feature already disabled."
    } else {
        Disable-WindowsOptionalFeature -Online -FeatureName "Recall" -Remove -NoRestart -ErrorAction Stop | Out-Null
        $after = Get-WindowsOptionalFeature -Online -FeatureName "Recall" -ErrorAction Stop
        Write-Log ("Recall feature state is now {0}. Restart required to finish removal." -f $after.State)
    }
} catch {
    Write-Log ("Recall feature not present on this PC, which is normal off Copilot+: {0}" -f $_.Exception.Message)
}

Write-Log "Removing the Microsoft Copilot store app. Microsoft 365 Copilot is left installed."
$removed = 0
Get-AppxPackage -AllUsers -ErrorAction SilentlyContinue |
    Where-Object { $_.Name -eq "Microsoft.Copilot" } |
    ForEach-Object {
        Write-Log ("Removing {0}" -f $_.PackageFullName)
        try {
            Remove-AppxPackage -Package $_.PackageFullName -AllUsers -ErrorAction Stop
            $removed++
        } catch {
            Write-Log ("Could not remove {0}: {1}" -f $_.PackageFullName, $_.Exception.Message)
        }
    }

Get-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue |
    Where-Object { $_.DisplayName -eq "Microsoft.Copilot" } |
    ForEach-Object {
        Write-Log ("Deprovisioning {0}" -f $_.PackageName)
        try {
            Remove-AppxProvisionedPackage -Online -PackageName $_.PackageName -ErrorAction Stop | Out-Null
        } catch {
            Write-Log ("Could not deprovision {0}: {1}" -f $_.PackageName, $_.Exception.Message)
        }
    }

$stillThere = @(Get-AppxPackage -AllUsers -ErrorAction SilentlyContinue | Where-Object { $_.Name -eq "Microsoft.Copilot" })
if ($stillThere.Count -eq 0) {
    Write-Log "Microsoft Copilot store app is not installed."
} else {
    Write-Log ("Microsoft Copilot is still installed for {0} package(s). Windows may be blocking removal on this edition." -f $stillThere.Count)
    $failed.Add("Microsoft.Copilot")
}

if (Get-Command winget -ErrorAction SilentlyContinue) {
    Write-Log "winget uninstall is a second pass and is safe to fail if the app is already gone."
    & winget uninstall --id Microsoft.Copilot --exact --disable-interactivity --accept-source-agreements 2>&1 |
        ForEach-Object { Write-Log ("winget: {0}" -f $_) }
}

Write-Host ""
if ($failed.Count -eq 0) {
    Write-Host "Verified. Every policy value written by this script read back correctly."
    Write-Log "Finished with all policy writes verified."
} else {
    Write-Host "Finished with problems. These did not stick:"
    $failed | ForEach-Object { Write-Host "  $_"; Write-Log "UNVERIFIED: $_" }
}
Write-Host ""
Write-Host "Sign out or restart. This script does not restart Explorer, because doing that from the admin prompt can leave Explorer running as admin."
Write-Host "Log: $log"
Write-Host ""
Write-Host "Still manual, because Windows has no stable switch for them:"
Write-Host "  Settings > Apps > Actions -> turn off File Explorer AI actions"
Write-Host "  Settings > System > AI components -> Experimental agentic features Off"
Write-Host "  OneDrive Summarize stays available while Microsoft 365 Copilot is signed in"
Write-Host ""
if ($failed.Count -gt 0) { exit 1 }
exit 0
