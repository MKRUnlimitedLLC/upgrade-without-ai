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
    # Automatic checks ask about the same result at most once a day.
    # A manual check always asks.
    switch ($Source) {
        "Update" { return 20 }
        "Logon" { return 20 }
        "Daily" { return 20 }
        default { return 0 }
    }
}

function Get-WindowsAISettingLabel {
    param([string]$Name)
    switch ($Name) {
        "AllowRecallEnablement" { return "Recall" }
        "DisableAIDataAnalysis" { return "Recall snapshots" }
        "DisableClickToDo" { return "Click to Do" }
        "DisableSettingsAgent" { return "Settings agent" }
        "RemoveMicrosoftCopilotApp" { return "Copilot app policy" }
        "TurnOffWindowsCopilot" { return "Copilot" }
        "DisableCocreator" { return "Paint Cocreator" }
        "DisableGenerativeFill" { return "Paint Generative Fill" }
        "DisableImageCreator" { return "Paint Image Creator" }
        "ShowCopilotButton" { return "Copilot button" }
        "Microsoft.Copilot" { return "Copilot app" }
        default { return $Name }
    }
}

function Test-WindowsAIShouldSkipScan {
    param(
        [string]$Source,
        $LastCheckedUtc,
        [string]$LastSource,
        [datetime]$NowUtc
    )

    # Manual checks always look. Update bursts (many "installed" events at once)
    # look once. Sign-in skips only another sign-in, so a sign-in after an update
    # still looks. The daily check is only a fallback when nothing else ran recently.
    if ($Source -eq "Manual") {
        return $false
    }
    if ([string]::IsNullOrWhiteSpace([string]$LastCheckedUtc)) {
        return $false
    }

    $last = ([datetime]$LastCheckedUtc).ToUniversalTime()
    $elapsedMinutes = ($NowUtc.ToUniversalTime() - $last).TotalMinutes
    if ($elapsedMinutes -lt 0) {
        return $false
    }

    switch ($Source) {
        "Update" { return ($LastSource -eq "Update" -and $elapsedMinutes -lt 30) }
        "Logon" { return ($LastSource -eq "Logon" -and $elapsedMinutes -lt (12 * 60)) }
        "Daily" { return ($elapsedMinutes -lt (12 * 60)) }
        default { return $false }
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

function Read-WindowsAIPolicyKey {
    param([Parameter(Mandatory = $true)][string]$Path)

    # One open per key. Missing keys are "not set", not a read failure.
    $values = @{}
    try {
        $item = Get-ItemProperty -LiteralPath $Path -ErrorAction Stop
    } catch {
        $notFound = $_.CategoryInfo.Category -eq "ObjectNotFound" -or $_.FullyQualifiedErrorId -like "PathNotFound*"
        if ($notFound) {
            return ,$values
        }
        throw
    }

    foreach ($prop in $item.PSObject.Properties) {
        if ($prop.Name -eq "PSPath" -or $prop.Name -eq "PSParentPath" -or $prop.Name -eq "PSChildName" -or $prop.Name -eq "PSDrive" -or $prop.Name -eq "PSProvider") {
            continue
        }
        $values[$prop.Name] = $prop.Value
    }
    return ,$values
}

function Read-WindowsAIPolicyValue {
    param(
        [string]$Path,
        [string]$Name
    )
    $values = Read-WindowsAIPolicyKey -Path $Path
    if ($values.ContainsKey($Name)) {
        $value = $values[$Name]
        if ($null -eq $value -or ($value -is [string] -and $value -eq "")) {
            return $null
        }
        return [int]$value
    }
    return $null
}

function Get-WindowsAIInstalledCopilotPackages {
    param([scriptblock]$ListPackages)

    $name = Get-WindowsAICopilotPackageName
    if (-not $ListPackages) {
        # Current user only. Enumerating every account needs admin, and this check
        # must not ask for admin. Yes on the prompt runs the disable script, which
        # removes the app for all users.
        $ListPackages = {
            if (-not (Get-Command Get-AppxPackage -ErrorAction SilentlyContinue)) {
                return @()
            }
            return @(Get-AppxPackage -Name $name -ErrorAction SilentlyContinue)
        }.GetNewClosure()
    }

    @(
        & $ListPackages |
            Where-Object { $null -ne $_ -and $_.Name -eq $name }
    )
}

function Add-WindowsAIDriftFinding {
    param(
        $FindingsList,
        $Policy,
        $Actual,
        [bool]$ReadFailed
    )

    $label = Get-WindowsAISettingLabel -Name $Policy.Name
    if ($ReadFailed) {
        [void]$FindingsList.Add([pscustomobject]@{
            Kind = "ReadError"
            Path = $Policy.Path
            Name = $Policy.Name
            Label = $label
            Expected = [int]$Policy.Value
            Actual = $null
            Message = ("Could not check {0}." -f $label)
        })
        return
    }

    $missing = $null -eq $Actual -or ($Actual -is [string] -and $Actual -eq "")
    if ($missing -or [int]$Actual -ne [int]$Policy.Value) {
        $actualValue = $null
        if (-not $missing) {
            $actualValue = [int]$Actual
        }
        [void]$FindingsList.Add([pscustomobject]@{
            Kind = "Policy"
            Path = $Policy.Path
            Name = $Policy.Name
            Label = $label
            Expected = [int]$Policy.Value
            Actual = $actualValue
            Message = ("{0} is back on." -f $label)
        })
    }
}

function Get-WindowsAIFindings {
    param(
        [scriptblock]$GetPolicyValue,
        [Parameter(Mandatory = $true)]
        [scriptblock]$GetCopilotPackages,
        [scriptblock]$GetPolicyKey
    )

    if (-not $GetPolicyValue -and -not $GetPolicyKey) {
        throw "Get-WindowsAIFindings needs GetPolicyValue or GetPolicyKey."
    }

    $findings = New-Object System.Collections.Generic.List[object]
    $policies = @(Get-WindowsAIExpectedPolicy)

    if ($GetPolicyKey) {
        $paths = New-Object System.Collections.Generic.List[string]
        $grouped = @{}
        foreach ($policy in $policies) {
            if (-not $grouped.ContainsKey($policy.Path)) {
                [void]$paths.Add($policy.Path)
                $grouped[$policy.Path] = New-Object System.Collections.Generic.List[object]
            }
            [void]$grouped[$policy.Path].Add($policy)
        }

        foreach ($path in $paths) {
            $snapshot = $null
            $readFailed = $false
            try {
                $snapshot = & $GetPolicyKey $path
            } catch {
                $readFailed = $true
            }
            foreach ($policy in $grouped[$path]) {
                $actual = $null
                if (-not $readFailed -and $snapshot -is [System.Collections.IDictionary] -and $snapshot.Contains($policy.Name)) {
                    $actual = $snapshot[$policy.Name]
                }
                Add-WindowsAIDriftFinding -FindingsList $findings -Policy $policy -Actual $actual -ReadFailed $readFailed
            }
        }
    } else {
        foreach ($policy in $policies) {
            $actual = $null
            $readFailed = $false
            try {
                $actual = & $GetPolicyValue $policy.Path $policy.Name
            } catch {
                $readFailed = $true
            }
            Add-WindowsAIDriftFinding -FindingsList $findings -Policy $policy -Actual $actual -ReadFailed $readFailed
        }
    }

    $packages = @(
        & $GetCopilotPackages |
            Where-Object { $null -ne $_ }
    )
    if ($packages.Count -gt 0) {
        $name = Get-WindowsAICopilotPackageName
        $label = Get-WindowsAISettingLabel -Name $name
        [void]$findings.Add([pscustomobject]@{
            Kind = "App"
            Path = "AppX"
            Name = $name
            Label = $label
            Expected = "NotInstalled"
            Actual = $packages.Count
            Message = "The Copilot app is installed."
        })
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
    [void]$lines.Add("Some AI features are back on:")
    [void]$lines.Add("")
    $seen = @{}
    foreach ($finding in @($Findings)) {
        if ($null -eq $finding) { continue }
        $bullet = [string]$finding.Label
        if ([string]::IsNullOrWhiteSpace($bullet)) {
            $bullet = [string]$finding.Message
        }
        if ([string]::IsNullOrWhiteSpace($bullet)) { continue }
        if ($seen.ContainsKey($bullet)) { continue }
        $seen[$bullet] = $true
        [void]$lines.Add("- $bullet")
    }
    [void]$lines.Add("")
    [void]$lines.Add("Click Yes to run Upgrade without AI again. Windows will ask for administrator approval.")
    [void]$lines.Add("This does not turn off Defender or Windows Update, and it does not remove Phi Silica or OneDrive Summarize.")
    [void]$lines.Add("")
    [void]$lines.Add("Click No to be reminded tomorrow. To leave them on and stop these reminders, double-click Restore Windows AI.")
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
    $description = "Checks whether AI features turned off by Upgrade without AI have come back. Does not change Windows Update or Defender."

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
        $LastNotifiedUtc,
        $LastCheckedUtc,
        [string]$LastSource
    )

    $path = Get-WindowsAIWatcherStatePath
    $hasCheck = -not [string]::IsNullOrWhiteSpace([string]$LastCheckedUtc)
    if ([string]::IsNullOrWhiteSpace($Fingerprint) -and -not $hasCheck) {
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
    $checked = $null
    if ($hasCheck) {
        $checked = ([datetime]$LastCheckedUtc).ToUniversalTime().ToString("o")
    }
    $payload = [pscustomobject]@{
        Fingerprint = $Fingerprint
        LastNotifiedUtc = $when
        LastCheckedUtc = $checked
        LastSource = $LastSource
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
        [scriptblock]$GetPolicyKey,
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
    if (-not $GetPolicyKey -and -not $GetPolicyValue) {
        $GetPolicyKey = { param($Path) Read-WindowsAIPolicyKey -Path $Path }
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
            param($Fingerprint, $LastNotifiedUtc, $LastCheckedUtc, $LastSource)
            Write-WindowsAIWatcherState -Fingerprint $Fingerprint -LastNotifiedUtc $LastNotifiedUtc -LastCheckedUtc $LastCheckedUtc -LastSource $LastSource
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

    & $WriteLog ("Check started ({0})." -f $Source)

    # Restoring Windows AI is a choice. Do not read the registry or the Copilot app.
    $userRestored = [bool](& $TestUserRestored)
    if ($userRestored) {
        $prior = & $ReadState
        if ($prior -and -not [string]::IsNullOrWhiteSpace([string]$prior.Fingerprint)) {
            & $WriteState -Fingerprint "" -LastNotifiedUtc $null
        }
        & $WriteLog "Windows AI was restored on purpose. Not checking and not asking."
        return [pscustomobject]@{
            ShouldNotify = $false
            ExitCode = 0
            Reason = "UserRestored"
            Fingerprint = ""
            Findings = @()
        }
    }

    $state = & $ReadState
    $lastFingerprint = ""
    $lastNotified = $null
    $lastChecked = $null
    $lastSource = ""
    if ($state) {
        $lastFingerprint = [string]$state.Fingerprint
        $lastNotified = $state.LastNotifiedUtc
        $lastChecked = $state.LastCheckedUtc
        $lastSource = [string]$state.LastSource
    }

    if (Test-WindowsAIShouldSkipScan -Source $Source -LastCheckedUtc $lastChecked -LastSource $lastSource -NowUtc ([datetime]$NowUtc)) {
        & $WriteLog "Skipped. A recent check already covered this."
        return [pscustomobject]@{
            ShouldNotify = $false
            ExitCode = 0
            Reason = "Skipped"
            Fingerprint = $lastFingerprint
            Findings = @()
        }
    }

    $findingArgs = @{ GetCopilotPackages = $GetCopilotPackages }
    if ($GetPolicyKey) {
        $findingArgs["GetPolicyKey"] = $GetPolicyKey
    } else {
        $findingArgs["GetPolicyValue"] = $GetPolicyValue
    }
    $findings = @(Get-WindowsAIFindings @findingArgs)

    $decision = Get-WindowsAIWatchDecision `
        -Findings $findings `
        -UserRestored $false `
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

    $saveFingerprint = ""
    $saveNotified = $null
    $stampCheck = $true
    if ($decision.Reason -eq "Cooldown") {
        $saveFingerprint = $lastFingerprint
        $saveNotified = $lastNotified
    } elseif ($decision.ShouldNotify -and -not $Quiet) {
        $answer = & $Prompt -Findings @($decision.Findings)
        $accepted = Test-WindowsAIUserAccepted -Answer $answer
        $declined = Test-WindowsAIUserDeclined -Answer $answer
        if ($accepted -or $declined) {
            $saveFingerprint = $decision.Fingerprint
            $saveNotified = ([datetime]$NowUtc)
        } else {
            # The message did not show. Try again next time instead of waiting a day.
            $stampCheck = $false
            & $WriteLog "Could not show a message. Run UpgradeWithoutAI.bat to turn these off again."
        }
        if ($accepted) {
            & $WriteLog "Starting Upgrade without AI."
            & $Reapply $ScriptRoot
        } elseif ($declined) {
            & $WriteLog "Not now. The same reminder waits until tomorrow."
        }
    }

    if ($stampCheck) {
        & $WriteState -Fingerprint $saveFingerprint -LastNotifiedUtc $saveNotified -LastCheckedUtc ([datetime]$NowUtc) -LastSource $Source
    }

    return $decision
}
