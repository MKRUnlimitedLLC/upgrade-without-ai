#Requires -Version 5.1
<#
  Shared check logic for Upgrade without AI.
  The expected off values are the same ones Disable-WindowsAI.ps1 writes.
  This file does not invent policy values and does not change Defender or Windows Update.
#>

$ErrorActionPreference = "Continue"

function Get-WindowsAIExpectedPolicy {
    @(
        [pscustomobject]@{ Path = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsAI"; Name = "AllowRecallEnablement"; Value = 0 }
        [pscustomobject]@{ Path = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsAI"; Name = "DisableAIDataAnalysis"; Value = 1 }
        [pscustomobject]@{ Path = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsAI"; Name = "DisableClickToDo"; Value = 1 }
        [pscustomobject]@{ Path = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsAI"; Name = "DisableSettingsAgent"; Value = 1 }
        [pscustomobject]@{ Path = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsAI"; Name = "RemoveMicrosoftCopilotApp"; Value = 1 }
        [pscustomobject]@{ Path = "HKCU:\SOFTWARE\Policies\Microsoft\Windows\WindowsAI"; Name = "DisableAIDataAnalysis"; Value = 1 }
        [pscustomobject]@{ Path = "HKCU:\SOFTWARE\Policies\Microsoft\Windows\WindowsAI"; Name = "DisableClickToDo"; Value = 1 }
        [pscustomobject]@{ Path = "HKCU:\SOFTWARE\Policies\Microsoft\Windows\WindowsAI"; Name = "RemoveMicrosoftCopilotApp"; Value = 1 }
        [pscustomobject]@{ Path = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsCopilot"; Name = "TurnOffWindowsCopilot"; Value = 1 }
        [pscustomobject]@{ Path = "HKCU:\SOFTWARE\Policies\Microsoft\Windows\WindowsCopilot"; Name = "TurnOffWindowsCopilot"; Value = 1 }
        [pscustomobject]@{ Path = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Paint"; Name = "DisableCocreator"; Value = 1 }
        [pscustomobject]@{ Path = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Paint"; Name = "DisableGenerativeFill"; Value = 1 }
        [pscustomobject]@{ Path = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Paint"; Name = "DisableImageCreator"; Value = 1 }
        [pscustomobject]@{ Path = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced"; Name = "ShowCopilotButton"; Value = 0 }
    )
}

function Get-WindowsAICopilotPackageName {
    "Microsoft.Copilot"
}

function Get-WindowsAIUserRestoredMarkerName {
    "user-restored.marker"
}

function Join-WindowsAIPath {
    param(
        [string]$Parent,
        [string]$Child
    )
    # These are Windows paths. Join-Path on another OS treats "C:" as a drive.
    return ($Parent.TrimEnd('\') + '\' + $Child)
}

function Get-WindowsAIProgramDataDirectory {
    param([string]$ProgramDataRoot)
    if (-not $ProgramDataRoot) {
        if ($env:ProgramData) {
            $ProgramDataRoot = $env:ProgramData
        } else {
            $ProgramDataRoot = "C:\ProgramData"
        }
    }
    Join-WindowsAIPath -Parent $ProgramDataRoot -Child "UpgradeWithoutAI"
}

function Get-WindowsAIUserRestoredMarkerPath {
    param([string]$ProgramDataRoot)
    Join-WindowsAIPath -Parent (Get-WindowsAIProgramDataDirectory -ProgramDataRoot $ProgramDataRoot) -Child (Get-WindowsAIUserRestoredMarkerName)
}

function Get-WindowsAIWatcherCooldownHours {
    param([string]$Source = "Manual")
    switch ($Source) {
        "Update" { return 3 }
        "Logon" { return 20 }
        "Daily" { return 20 }
        default { return 0 }
    }
}

function Get-WindowsAIWatcherStateDirectory {
    $root = $env:LOCALAPPDATA
    if (-not $root) {
        $root = [System.IO.Path]::GetTempPath()
    }
    Join-Path $root "UpgradeWithoutAI"
}

function Get-WindowsAIWatcherStatePath {
    Join-Path (Get-WindowsAIWatcherStateDirectory) "watcher-state.json"
}

function Get-WindowsAIWatcherLogPath {
    Join-Path (Get-WindowsAIWatcherStateDirectory) "watcher.log"
}

function Read-WindowsAIPolicyValue {
    param(
        [string]$Path,
        [string]$Name
    )
    if (-not (Test-Path -LiteralPath $Path)) {
        return $null
    }
    $item = Get-ItemProperty -LiteralPath $Path -Name $Name -ErrorAction SilentlyContinue
    if ($null -eq $item) {
        return $null
    }
    $value = $item.$Name
    if ($null -eq $value) {
        return $null
    }
    return [int]$value
}

function Get-WindowsAIInstalledCopilotPackages {
    param([scriptblock]$ListPackages)

    $name = Get-WindowsAICopilotPackageName
    if (-not $ListPackages) {
        $ListPackages = {
            if (-not (Get-Command Get-AppxPackage -ErrorAction SilentlyContinue)) {
                return @()
            }
            # The disable script checks -AllUsers. That needs admin. The watcher runs
            # as the signed-in user, so fall back to that user's packages.
            try {
                return @(Get-AppxPackage -AllUsers -ErrorAction Stop)
            } catch {
                return @(Get-AppxPackage -ErrorAction SilentlyContinue)
            }
        }
    }

    @(
        & $ListPackages |
            Where-Object { $null -ne $_ -and $_.Name -eq $name }
    )
}

function Get-WindowsAIFindings {
    param(
        [Parameter(Mandatory = $true)]
        [scriptblock]$GetPolicyValue,
        [Parameter(Mandatory = $true)]
        [scriptblock]$GetCopilotPackages
    )

    $findings = New-Object System.Collections.Generic.List[object]
    foreach ($policy in @(Get-WindowsAIExpectedPolicy)) {
        $actual = $null
        $readFailed = $false
        $readError = $null
        try {
            $actual = & $GetPolicyValue $policy.Path $policy.Name
        } catch {
            $readFailed = $true
            $readError = $_.Exception.Message
        }

        if ($readFailed) {
            $findings.Add([pscustomobject]@{
                Kind = "ReadError"
                Path = $policy.Path
                Name = $policy.Name
                Expected = [int]$policy.Value
                Actual = $null
                Message = ("Could not read {0}\{1}: {2}" -f $policy.Path, $policy.Name, $readError)
            }) | Out-Null
            continue
        }

        $missing = $null -eq $actual -or ($actual -is [string] -and $actual -eq "")
        if ($missing -or [int]$actual -ne [int]$policy.Value) {
            $shown = "missing"
            $actualValue = $null
            if (-not $missing) {
                $actualValue = [int]$actual
                $shown = [string]$actualValue
            }
            $findings.Add([pscustomobject]@{
                Kind = "Policy"
                Path = $policy.Path
                Name = $policy.Name
                Expected = [int]$policy.Value
                Actual = $actualValue
                Message = ("{0}\{1} is {2}; expected {3}." -f $policy.Path, $policy.Name, $shown, [int]$policy.Value)
            }) | Out-Null
        }
    }

    $packages = @(
        & $GetCopilotPackages |
            Where-Object { $null -ne $_ }
    )
    if ($packages.Count -gt 0) {
        $name = Get-WindowsAICopilotPackageName
        $findings.Add([pscustomobject]@{
            Kind = "App"
            Path = "AppX"
            Name = $name
            Expected = "NotInstalled"
            Actual = $packages.Count
            Message = ("{0} store app is installed ({1} package(s))." -f $name, $packages.Count)
        }) | Out-Null
    }

    # Emit each finding. An empty list must produce no output; wrapping an empty
    # array makes @(...) count 1 on Windows PowerShell and PowerShell 7.
    foreach ($item in $findings) {
        Write-Output $item
    }
}

function Get-WindowsAIFindingFingerprint {
    param([object[]]$Findings)
    $lines = @(
        @($Findings) |
            Where-Object { $null -ne $_ } |
            ForEach-Object { "{0}|{1}|{2}|{3}" -f $_.Kind, $_.Path, $_.Name, $_.Actual } |
            Sort-Object
    )
    return ($lines -join "`n")
}

function Get-WindowsAIWatchDecision {
    param(
        [object[]]$Findings = @(),
        [bool]$UserRestored,
        [datetime]$NowUtc,
        [string]$LastFingerprint = "",
        $LastNotifiedUtc,
        [int]$CooldownHours = 0
    )

    $findingList = @($Findings | Where-Object { $null -ne $_ })
    $fingerprint = Get-WindowsAIFindingFingerprint -Findings $findingList
    $now = $NowUtc.ToUniversalTime()

    if ($findingList.Count -eq 0) {
        return [pscustomobject]@{
            ShouldNotify = $false
            ExitCode = 0
            Reason = "Clean"
            Fingerprint = $fingerprint
            Findings = $findingList
        }
    }

    if ($UserRestored) {
        return [pscustomobject]@{
            ShouldNotify = $false
            ExitCode = 0
            Reason = "UserRestored"
            Fingerprint = $fingerprint
            Findings = $findingList
        }
    }

    $notify = $true
    $reason = "Drift"
    $hasLast = -not [string]::IsNullOrWhiteSpace([string]$LastNotifiedUtc)
    if ($CooldownHours -gt 0 -and $LastFingerprint -eq $fingerprint -and $hasLast) {
        $last = ([datetime]$LastNotifiedUtc).ToUniversalTime()
        $elapsedHours = ($now - $last).TotalHours
        if ($elapsedHours -lt $CooldownHours) {
            $notify = $false
            $reason = "Cooldown"
        }
    }

    return [pscustomobject]@{
        ShouldNotify = $notify
        ExitCode = 2
        Reason = $reason
        Fingerprint = $fingerprint
        Findings = $findingList
    }
}

function Get-WindowsAIDriftPromptText {
    param([object[]]$Findings)
    $lines = New-Object System.Collections.Generic.List[string]
    [void]$lines.Add("Some Windows AI settings that Upgrade without AI turns off are on again.")
    [void]$lines.Add("")
    [void]$lines.Add("This check does not disable Defender or Windows Update, and it does not remove Phi Silica or OneDrive Summarize.")
    [void]$lines.Add("")
    foreach ($finding in @($Findings)) {
        if ($null -ne $finding -and $finding.Message) {
            [void]$lines.Add("- " + $finding.Message)
        }
    }
    [void]$lines.Add("")
    [void]$lines.Add("Click Yes to run Upgrade without AI again. Windows will ask for admin approval.")
    [void]$lines.Add("Click No to be reminded later. Run Restore Windows AI if you want these features left on. That stops these reminders.")
    return ($lines -join [Environment]::NewLine)
}

function Get-WindowsAIReapplyCommand {
    param([Parameter(Mandatory = $true)][string]$ScriptRoot)

    $bat = Join-Path $ScriptRoot "UpgradeWithoutAI.bat"
    if (Test-Path -LiteralPath $bat) {
        return [pscustomobject]@{
            FilePath = $bat
            ArgumentList = @()
        }
    }

    $disable = Join-Path $ScriptRoot "Disable-WindowsAI.ps1"
    return [pscustomobject]@{
        FilePath = "powershell.exe"
        ArgumentList = @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $disable)
    }
}

function Invoke-WindowsAIReapply {
    param(
        [Parameter(Mandatory = $true)][string]$ScriptRoot,
        [scriptblock]$Start
    )

    $cmd = Get-WindowsAIReapplyCommand -ScriptRoot $ScriptRoot
    if (-not $Start) {
        $Start = {
            param($FilePath, $ArgumentList)
            if ($null -ne $ArgumentList -and @($ArgumentList).Count -gt 0) {
                Start-Process -FilePath $FilePath -ArgumentList $ArgumentList
            } else {
                Start-Process -FilePath $FilePath
            }
        }
    }
    & $Start -FilePath $cmd.FilePath -ArgumentList @($cmd.ArgumentList)
    return $cmd
}

function Get-WindowsAIWatcherExecutableArguments {
    param(
        [Parameter(Mandatory = $true)][string]$ScriptPath,
        [Parameter(Mandatory = $true)][string]$Source
    )
    '-NoProfile -STA -ExecutionPolicy Bypass -WindowStyle Hidden -File "{0}" -Source {1}' -f $ScriptPath, $Source
}

function Get-WindowsAIWatcherTaskDefinition {
    param([Parameter(Mandatory = $true)][string]$ScriptRoot)

    $watch = Join-Path $ScriptRoot "Watch-WindowsAI.ps1"
    $taskPath = "\UpgradeWithoutAI\"
    $description = "Checks whether Upgrade without AI policy values and the Microsoft Copilot app are still off. Does not change Windows Update or Defender."

    @(
        [pscustomobject]@{
            TaskPath = $taskPath
            TaskName = "WatchAfterUpdate"
            Source = "Update"
            Description = $description
            Execute = "powershell.exe"
            Arguments = (Get-WindowsAIWatcherExecutableArguments -ScriptPath $watch -Source "Update")
            Trigger = [pscustomobject]@{
                Kind = "WindowsUpdateInstalled"
                LogName = "Microsoft-Windows-WindowsUpdateClient/Operational"
                Provider = "Microsoft-Windows-WindowsUpdateClient"
                EventId = 19
                DelayMinutes = 3
            }
        }
        [pscustomobject]@{
            TaskPath = $taskPath
            TaskName = "WatchAtLogon"
            Source = "Logon"
            Description = $description
            Execute = "powershell.exe"
            Arguments = (Get-WindowsAIWatcherExecutableArguments -ScriptPath $watch -Source "Logon")
            Trigger = [pscustomobject]@{
                Kind = "Logon"
                DelayMinutes = 2
            }
        }
        [pscustomobject]@{
            TaskPath = $taskPath
            TaskName = "WatchDaily"
            Source = "Daily"
            Description = $description
            Execute = "powershell.exe"
            Arguments = (Get-WindowsAIWatcherExecutableArguments -ScriptPath $watch -Source "Daily")
            Trigger = [pscustomobject]@{
                Kind = "Daily"
                At = "09:15"
                RandomDelayMinutes = 30
            }
        }
    )
}

function Get-WindowsAIUpdateEventQuery {
    param(
        [Parameter(Mandatory = $true)][string]$LogName,
        [Parameter(Mandatory = $true)][string]$Provider,
        [Parameter(Mandatory = $true)][int]$EventId
    )

@"
<QueryList>
  <Query Id="0" Path="$LogName">
    <Select Path="$LogName">*[System[Provider[@Name='$Provider'] and (EventID=$EventId)]]</Select>
  </Query>
</QueryList>
"@.Trim()
}

function Read-WindowsAIWatcherState {
    $path = Get-WindowsAIWatcherStatePath
    if (-not (Test-Path -LiteralPath $path)) {
        return $null
    }
    try {
        $raw = Get-Content -LiteralPath $path -Raw -Encoding UTF8
        if ([string]::IsNullOrWhiteSpace($raw)) {
            return $null
        }
        return ($raw | ConvertFrom-Json)
    } catch {
        return $null
    }
}

function Write-WindowsAIWatcherState {
    param(
        [string]$Fingerprint,
        $LastNotifiedUtc
    )

    $path = Get-WindowsAIWatcherStatePath
    if ([string]::IsNullOrWhiteSpace($Fingerprint)) {
        if (Test-Path -LiteralPath $path) {
            Remove-Item -LiteralPath $path -Force
        }
        return
    }

    $dir = Split-Path -Parent $path
    if (-not (Test-Path -LiteralPath $dir)) {
        New-Item -ItemType Directory -Force -Path $dir | Out-Null
    }

    $when = $null
    if ($LastNotifiedUtc) {
        $when = ([datetime]$LastNotifiedUtc).ToUniversalTime().ToString("o")
    }
    $payload = [pscustomobject]@{
        Fingerprint = $Fingerprint
        LastNotifiedUtc = $when
    }
    $json = $payload | ConvertTo-Json -Compress
    [System.IO.File]::WriteAllText($path, $json)
}

function Write-WindowsAIWatcherLog {
    param([string]$Message)
    $line = "{0}  {1}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), $Message
    try {
        $path = Get-WindowsAIWatcherLogPath
        $dir = Split-Path -Parent $path
        if (-not (Test-Path -LiteralPath $dir)) {
            New-Item -ItemType Directory -Force -Path $dir | Out-Null
        }
        Add-Content -LiteralPath $path -Value $line -Encoding UTF8
    } catch {
        # The check result still matters if the log cannot be written.
    }
    Write-Host $Message
}

function Test-WindowsAIUserAccepted {
    param($Answer)
    return ($Answer -eq $true -or $Answer -eq "Yes")
}

function Test-WindowsAIUserDeclined {
    param($Answer)
    return ($Answer -eq $false -or $Answer -eq "No")
}

function Invoke-WindowsAIWatch {
    param(
        [switch]$Quiet,
        [string]$Source = "Manual",
        [scriptblock]$GetPolicyValue,
        [scriptblock]$GetCopilotPackages,
        [scriptblock]$TestUserRestored,
        [scriptblock]$ReadState,
        [scriptblock]$WriteState,
        [scriptblock]$WriteLog,
        [scriptblock]$Prompt,
        [scriptblock]$Reapply,
        [string]$ScriptRoot,
        $NowUtc
    )

    if (-not $ScriptRoot) {
        $ScriptRoot = $script:UpgradeWithoutAIRoot
    }
    if (-not $GetPolicyValue) {
        $GetPolicyValue = { param($Path, $Name) Read-WindowsAIPolicyValue -Path $Path -Name $Name }
    }
    if (-not $GetCopilotPackages) {
        $GetCopilotPackages = { Get-WindowsAIInstalledCopilotPackages }
    }
    if (-not $TestUserRestored) {
        $TestUserRestored = {
            $marker = Get-WindowsAIUserRestoredMarkerPath
            Test-Path -LiteralPath $marker
        }
    }
    if (-not $ReadState) {
        $ReadState = { Read-WindowsAIWatcherState }
    }
    if (-not $WriteState) {
        $WriteState = {
            param($Fingerprint, $LastNotifiedUtc)
            Write-WindowsAIWatcherState -Fingerprint $Fingerprint -LastNotifiedUtc $LastNotifiedUtc
        }
    }
    if (-not $WriteLog) {
        $WriteLog = { param($Message) Write-WindowsAIWatcherLog -Message $Message }
    }
    if (-not $Prompt) {
        $Prompt = {
            param($Findings)
            if (Get-Command Show-WindowsAIDriftPrompt -ErrorAction SilentlyContinue) {
                return (Show-WindowsAIDriftPrompt -Findings $Findings)
            }
            return "Unavailable"
        }
    }
    if (-not $Reapply) {
        $Reapply = { param($Root) Invoke-WindowsAIReapply -ScriptRoot $Root }
    }
    if (-not $NowUtc) {
        $NowUtc = [datetime]::UtcNow
    }

    & $WriteLog ("Upgrade without AI watcher started. Source={0}." -f $Source)

    $findings = @(Get-WindowsAIFindings -GetPolicyValue $GetPolicyValue -GetCopilotPackages $GetCopilotPackages)
    $userRestored = [bool](& $TestUserRestored)
    $state = & $ReadState
    $lastFingerprint = ""
    $lastNotified = $null
    if ($state) {
        $lastFingerprint = [string]$state.Fingerprint
        $lastNotified = $state.LastNotifiedUtc
    }

    $decision = Get-WindowsAIWatchDecision `
        -Findings $findings `
        -UserRestored $userRestored `
        -NowUtc ([datetime]$NowUtc) `
        -LastFingerprint $lastFingerprint `
        -LastNotifiedUtc $lastNotified `
        -CooldownHours (Get-WindowsAIWatcherCooldownHours -Source $Source)

    & $WriteLog ("Check finished. Reason={0}; findings={1}; notify={2}." -f $decision.Reason, @($decision.Findings).Count, $decision.ShouldNotify)
    foreach ($finding in @($decision.Findings)) {
        if ($null -ne $finding) {
            & $WriteLog $finding.Message
        }
    }

    if ($decision.Reason -eq "Clean" -or $decision.Reason -eq "UserRestored") {
        # Drop any earlier reminder so a later real drift is not hidden by cooldown.
        & $WriteState -Fingerprint "" -LastNotifiedUtc $null
        return $decision
    }

    if ($decision.ShouldNotify -and -not $Quiet) {
        $answer = & $Prompt -Findings @($decision.Findings)
        if ((Test-WindowsAIUserAccepted -Answer $answer) -or (Test-WindowsAIUserDeclined -Answer $answer)) {
            & $WriteState -Fingerprint $decision.Fingerprint -LastNotifiedUtc ([datetime]$NowUtc)
        }
        if (Test-WindowsAIUserAccepted -Answer $answer) {
            & $WriteLog "User accepted. Starting Upgrade without AI."
            & $Reapply $ScriptRoot
        } elseif (Test-WindowsAIUserDeclined -Answer $answer) {
            & $WriteLog "User declined. The same result stays quiet until the cooldown ends or the result changes."
        } else {
            & $WriteLog "Could not show a prompt. Run UpgradeWithoutAI.bat to turn these off again."
        }
    }

    return $decision
}
