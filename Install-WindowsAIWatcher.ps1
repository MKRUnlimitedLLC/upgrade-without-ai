#Requires -Version 5.1
<#
  Registers per-user scheduled tasks that run Watch-WindowsAI.ps1.

  Post-update trigger: event 19, "Installation successful", in
  Microsoft-Windows-WindowsUpdateClient/Operational. The task waits 3 minutes
  so that install can settle. Event 19 is written once per update package, and
  it can fire before a feature update reboots. It can also fire while nobody
  is signed in. This task runs only in the signed-in user's session so it can
  show a prompt, so a missed event is not the only check.

  Fallbacks:
  - At sign-in, delayed 2 minutes, after the desktop is up.
  - Daily at 9:15 local time, with a 30 minute random delay.

  A burst of update events checks once. Sign-in after an update still
  checks. The daily check skips if anything ran in the last 12 hours.
  The same result is asked about at most once a day. A different result
  asks right away. RestoreWindowsAI.bat writes user-restored.marker,
  and every task stays quiet while that file exists.

  If the event trigger cannot be registered, sign-in and daily tasks are still
  installed. This script does not disable Defender or Windows Update.
#>
param(
    [switch]$Uninstall
)

$ErrorActionPreference = "Stop"

if ($env:PROCESSOR_ARCHITEW6432 -eq "AMD64") {
    $sysnative = Join-Path $env:WINDIR "Sysnative\WindowsPowerShell\v1.0\powershell.exe"
    if (Test-Path $sysnative) {
        $relaunch = @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $PSCommandPath)
        if ($Uninstall) { $relaunch += "-Uninstall" }
        & $sysnative @relaunch
        exit $LASTEXITCODE
    }
}

. (Join-Path $PSScriptRoot "WindowsAI.Common.ps1")

function ConvertTo-UpgradeWithoutAITaskDuration {
    param([int]$Minutes)
    [System.Xml.XmlConvert]::ToString([TimeSpan]::FromMinutes($Minutes))
}

function New-UpgradeWithoutAITrigger {
    param(
        $TriggerSpec,
        [string]$UserId
    )

    switch ($TriggerSpec.Kind) {
        "WindowsUpdateInstalled" {
            $query = Get-WindowsAIUpdateEventQuery -LogName $TriggerSpec.LogName -Provider $TriggerSpec.Provider -EventId $TriggerSpec.EventId
            $class = Get-CimClass -Namespace "Root/Microsoft/Windows/TaskScheduler" -ClassName "MSFT_TaskEventTrigger"
            $trigger = New-CimInstance -CimClass $class -ClientOnly
            $trigger.Enabled = $true
            $trigger.Subscription = $query
            $trigger.Delay = (ConvertTo-UpgradeWithoutAITaskDuration -Minutes ([int]$TriggerSpec.DelayMinutes))
            return $trigger
        }
        "Logon" {
            $trigger = New-ScheduledTaskTrigger -AtLogOn -User $UserId
            $trigger.Delay = (ConvertTo-UpgradeWithoutAITaskDuration -Minutes ([int]$TriggerSpec.DelayMinutes))
            return $trigger
        }
        "Daily" {
            $hours, $mins = ([string]$TriggerSpec.At).Split(":")
            $at = (Get-Date).Date.AddHours([int]$hours).AddMinutes([int]$mins)
            $trigger = New-ScheduledTaskTrigger -Daily -At $at
            if ($TriggerSpec.RandomDelayMinutes) {
                $trigger.RandomDelay = (ConvertTo-UpgradeWithoutAITaskDuration -Minutes ([int]$TriggerSpec.RandomDelayMinutes))
            }
            return $trigger
        }
        default {
            throw "Unknown trigger kind $($TriggerSpec.Kind)"
        }
    }
}

function Register-UpgradeWithoutAIWatcherTask {
    param(
        $Definition,
        [string]$UserId
    )

    $powershell = Join-Path $env:SystemRoot "System32\WindowsPowerShell\v1.0\powershell.exe"
    $execute = $Definition.Execute
    if (Test-Path $powershell) {
        $execute = $powershell
    }

    $action = New-ScheduledTaskAction -Execute $execute -Argument $Definition.Arguments
    $trigger = New-UpgradeWithoutAITrigger -TriggerSpec $Definition.Trigger -UserId $UserId
    $principal = New-ScheduledTaskPrincipal -UserId $UserId -LogonType Interactive -RunLevel Limited
    $settings = New-ScheduledTaskSettingsSet `
        -StartWhenAvailable `
        -AllowStartIfOnBatteries `
        -DontStopIfGoingOnBatteries `
        -MultipleInstances IgnoreNew `
        -ExecutionTimeLimit (New-TimeSpan -Hours 2)
    $settings.DisallowStartIfOnBatteries = $false
    $settings.StopIfGoingOnBatteries = $false

    Register-ScheduledTask `
        -TaskName $Definition.TaskName `
        -TaskPath $Definition.TaskPath `
        -Action $action `
        -Trigger $trigger `
        -Principal $principal `
        -Settings $settings `
        -Description $Definition.Description `
        -Force | Out-Null
}

$definitions = @(Get-WindowsAIWatcherTaskDefinition -ScriptRoot $PSScriptRoot)

if ($Uninstall) {
    foreach ($def in $definitions) {
        Unregister-ScheduledTask -TaskName $def.TaskName -TaskPath $def.TaskPath -Confirm:$false -ErrorAction SilentlyContinue
    }
    Write-Host "Removed the after-update check, if it was installed."
    exit 0
}

if (-not (Get-Command Register-ScheduledTask -ErrorAction SilentlyContinue)) {
    Write-Host "Register-ScheduledTask is not available. Install this watcher from Windows PowerShell on Windows."
    exit 1
}

$user = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
$updateFailed = $false
$installed = 0
foreach ($def in $definitions) {
    try {
        Register-UpgradeWithoutAIWatcherTask -Definition $def -UserId $user
        $installed++
    } catch {
        if ($def.Trigger.Kind -eq "WindowsUpdateInstalled") {
            $updateFailed = $true
            continue
        }
        Write-Host "Could not install the check. Try again from this folder."
        exit 1
    }
}

Write-Host ""
Write-Host "Installed the after-update check for $user."
Write-Host "It runs after Windows Update, when you sign in, and once a day if those did not run."
Write-Host "You only get a message when an AI feature this tool turns off is back on."
Write-Host "Click Yes to turn it off again. Windows asks for administrator approval only then."
if ($updateFailed) {
    Write-Host "Windows did not allow a schedule right after an update. Sign-in and daily checks are still installed."
} elseif ($installed -eq 0) {
    Write-Host "Nothing was installed."
    exit 1
}
Write-Host "Leave this folder where it is. Double-click UninstallWindowsAIWatcher.bat to remove the check."
exit 0
