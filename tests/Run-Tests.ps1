#Requires -Version 5.1
<#
  Runs the Pester 5 suite in ./tests.
  Usage: pwsh -NoProfile -File ./tests/Run-Tests.ps1
#>
$ErrorActionPreference = "Stop"

$pester = @(Get-Module -ListAvailable Pester | Where-Object { $_.Version.Major -eq 5 } | Sort-Object Version -Descending | Select-Object -First 1)
if (-not $pester) {
    if (-not (Get-PackageProvider -Name NuGet -ErrorAction SilentlyContinue)) {
        Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force -Scope CurrentUser | Out-Null
    }
    if (-not (Get-PSRepository -Name PSGallery -ErrorAction SilentlyContinue)) {
        Register-PSRepository -Default -ErrorAction SilentlyContinue
    }
    Set-PSRepository -Name PSGallery -InstallationPolicy Trusted
    Install-Module -Name Pester -MinimumVersion 5.0.0 -MaximumVersion 5.99.99 -Scope CurrentUser -Force -SkipPublisherCheck
}

Import-Module Pester -MinimumVersion 5.0.0 -MaximumVersion 5.99.99 -Force

$cfg = New-PesterConfiguration
$cfg.Run.Path = $PSScriptRoot
$cfg.Run.Exit = $true
$cfg.Output.Verbosity = "Detailed"
Invoke-Pester -Configuration $cfg
