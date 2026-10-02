#Requires -Version 5.1
<#
  Checks the policy values and Microsoft.Copilot app state that Disable-WindowsAI.ps1 writes.
  If an expected off value is missing or wrong, tells the signed-in user and can start UpgradeWithoutAI.bat.
  Does not disable Defender or Windows Update.
  Does not remove Phi Silica or turn off OneDrive Summarize.

  -Source Update is the post-update task. Logon and Daily are fallbacks.
  Manual is the default when you run this script yourself, and it always shows a current drift.
#>
param(
    [switch]$Quiet,
    [switch]$PassThru,
    [ValidateSet("Update", "Logon", "Daily", "Manual")]
    [string]$Source = "Manual"
)

$ErrorActionPreference = "Continue"
$script:UpgradeWithoutAIRoot = Split-Path -Parent $MyInvocation.MyCommand.Path

. (Join-Path $script:UpgradeWithoutAIRoot "WindowsAI.Common.ps1")

function Show-WindowsAIDriftPrompt {
    param($Findings)
    $text = Get-WindowsAIDriftPromptText -Findings $Findings
    try {
        Add-Type -AssemblyName System.Windows.Forms -ErrorAction Stop
        $result = [System.Windows.Forms.MessageBox]::Show(
            $text,
            "Upgrade without AI",
            [System.Windows.Forms.MessageBoxButtons]::YesNo,
            [System.Windows.Forms.MessageBoxIcon]::Warning,
            [System.Windows.Forms.MessageBoxDefaultButton]::Button1
        )
        if ($result -eq [System.Windows.Forms.DialogResult]::Yes) {
            return "Yes"
        }
        return "No"
    } catch {
        Write-Host "Could not show a prompt. Run UpgradeWithoutAI.bat to turn these off again."
        return "Unavailable"
    }
}

$dotSourced = $MyInvocation.InvocationName -eq "." -or ($MyInvocation.Line -match '^\s*\.\s+')
if (-not $dotSourced) {
    # A 32-bit host cannot see the 64-bit policy view or AppX packages. Relaunch, without elevating.
    if ($env:PROCESSOR_ARCHITEW6432 -eq "AMD64") {
        $sysnative = Join-Path $env:WINDIR "Sysnative\WindowsPowerShell\v1.0\powershell.exe"
        if (Test-Path $sysnative) {
            $relaunch = @("-NoProfile", "-STA", "-ExecutionPolicy", "Bypass", "-File", $PSCommandPath, "-Source", $Source)
            if ($Quiet) { $relaunch += "-Quiet" }
            if ($PassThru) { $relaunch += "-PassThru" }
            & $sysnative @relaunch
            exit $LASTEXITCODE
        }
    }

    try {
        $decision = Invoke-WindowsAIWatch -Quiet:$Quiet -Source $Source -ScriptRoot $script:UpgradeWithoutAIRoot
    } catch {
        Write-Host $_.Exception.Message
        exit 1
    }
    if ($Source -eq "Manual" -and -not $Quiet) {
        Write-Host ""
        Write-Host (Format-WindowsAIManualReport)
    }
    if ($PassThru) {
        $decision | ConvertTo-Json -Depth 6
    }
    exit $decision.ExitCode
}
