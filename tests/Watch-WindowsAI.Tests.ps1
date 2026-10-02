#Requires -Version 5.1

BeforeAll {
    $script:RepoRoot = Split-Path $PSScriptRoot -Parent
    . (Join-Path $script:RepoRoot "WindowsAI.Common.ps1")

    $script:FrozenPolicy = @(
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

    function Get-DisableScriptPolicies {
        param([string]$ScriptText)
        $vars = @{}
        foreach ($match in [regex]::Matches($ScriptText, '(?m)^\$(\w+)\s*=\s*"([^"]+)"\s*$')) {
            $vars[$match.Groups[1].Value] = $match.Groups[2].Value
        }
        $rows = @()
        foreach ($match in [regex]::Matches($ScriptText, 'Set-Dword\s+\$(\w+)\s+"([^"]+)"\s+(\d+)')) {
            $varName = $match.Groups[1].Value
            if (-not $vars.ContainsKey($varName)) {
                throw "No path assignment for $varName"
            }
            $rows += [pscustomobject]@{
                Path = $vars[$varName]
                Name = $match.Groups[2].Value
                Value = [int]$match.Groups[3].Value
            }
        }
        return $rows
    }

    function New-PolicyReader {
        param([hashtable]$Values)
        $captured = $Values
        return {
            param($Path, $Name)
            $key = "$Path|$Name"
            if ($captured.ContainsKey($key)) {
                return $captured[$key]
            }
            return $null
        }.GetNewClosure()
    }

    function Get-CleanPolicyValues {
        $map = @{}
        foreach ($policy in @($script:FrozenPolicy)) {
            $map["$($policy.Path)|$($policy.Name)"] = [int]$policy.Value
        }
        return $map
    }

    function Invoke-WatchForTest {
        param(
            [scriptblock]$GetPolicyValue,
            [scriptblock]$GetCopilotPackages = { @() },
            [bool]$UserRestored = $false,
            [string]$Source = "Manual",
            $State = $null,
            [scriptblock]$Prompt = { param($Findings) "Yes" },
            [switch]$Quiet,
            $NowUtc = [datetime]::Parse("2026-06-01T12:00:00Z")
        )

        $script:TestWatch = @{
            ReapplyRoot = $null
            Prompted = $false
            StateWrites = New-Object System.Collections.Generic.List[object]
        }
        $bag = $script:TestWatch
        $capturedRestored = $UserRestored
        $capturedState = $State
        $capturedPrompt = $Prompt

        Invoke-WindowsAIWatch `
            -Quiet:$Quiet `
            -Source $Source `
            -ScriptRoot $script:RepoRoot `
            -NowUtc $NowUtc `
            -GetPolicyValue $GetPolicyValue `
            -GetCopilotPackages $GetCopilotPackages `
            -TestUserRestored { $capturedRestored }.GetNewClosure() `
            -ReadState { $capturedState }.GetNewClosure() `
            -WriteState {
                param($Fingerprint, $LastNotifiedUtc)
                [void]$bag.StateWrites.Add([pscustomobject]@{
                    Fingerprint = $Fingerprint
                    LastNotifiedUtc = $LastNotifiedUtc
                })
            }.GetNewClosure() `
            -WriteLog { param($Message) } `
            -Prompt {
                param($Findings)
                $bag.Prompted = $true
                & $capturedPrompt $Findings
            }.GetNewClosure() `
            -Reapply {
                param($Root)
                $bag.ReapplyRoot = $Root
            }.GetNewClosure()
    }
}

Describe "policy values stay aligned with Disable-WindowsAI.ps1" {
    It "uses the same paths and dword values the disable script writes" {
        $disablePath = Join-Path $script:RepoRoot "Disable-WindowsAI.ps1"
        $fromScript = @(Get-DisableScriptPolicies -ScriptText (Get-Content -LiteralPath $disablePath -Raw))
        $fromCommon = @(Get-WindowsAIExpectedPolicy)

        $fromScript.Count | Should -Be $script:FrozenPolicy.Count
        $fromCommon.Count | Should -Be $script:FrozenPolicy.Count

        foreach ($frozen in $script:FrozenPolicy) {
            $scriptRow = @($fromScript | Where-Object { $_.Path -eq $frozen.Path -and $_.Name -eq $frozen.Name })
            $commonRow = @($fromCommon | Where-Object { $_.Path -eq $frozen.Path -and $_.Name -eq $frozen.Name })
            $scriptRow.Count | Should -Be 1
            $commonRow.Count | Should -Be 1
            [int]$scriptRow[0].Value | Should -Be ([int]$frozen.Value)
            [int]$commonRow[0].Value | Should -Be ([int]$frozen.Value)
        }
    }

    It "watches the Microsoft.Copilot package the disable script removes" {
        (Get-WindowsAICopilotPackageName) | Should -Be "Microsoft.Copilot"
        $disable = Get-Content -LiteralPath (Join-Path $script:RepoRoot "Disable-WindowsAI.ps1") -Raw
        $disable | Should -Match '"Microsoft\.Copilot"'
    }

    It "does not add Defender or Windows Update policy writes to the disable script" {
        $disable = Get-Content -LiteralPath (Join-Path $script:RepoRoot "Disable-WindowsAI.ps1") -Raw
        $disable | Should -Not -Match "DisableAntiSpyware"
        $disable | Should -Not -Match "NoAutoUpdate"
    }
}

Describe "drift detection" {
    It "reports nothing when every expected value is present and Copilot is absent" {
        $findings = @(Get-WindowsAIFindings -GetPolicyValue (New-PolicyReader -Values (Get-CleanPolicyValues)) -GetCopilotPackages { @() })
        $findings.Count | Should -Be 0

        $decision = Get-WindowsAIWatchDecision -Findings $findings -UserRestored $false -NowUtc ([datetime]::UtcNow) -CooldownHours 20
        $decision.ShouldNotify | Should -BeFalse
        $decision.ExitCode | Should -Be 0
        $decision.Reason | Should -Be "Clean"
    }

    It "detects a missing policy value" {
        $values = Get-CleanPolicyValues
        $values.Remove("HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsAI|DisableAIDataAnalysis")
        $findings = @(Get-WindowsAIFindings -GetPolicyValue (New-PolicyReader -Values $values) -GetCopilotPackages { @() })
        $findings.Count | Should -Be 1
        $findings[0].Kind | Should -Be "Policy"
        $findings[0].Name | Should -Be "DisableAIDataAnalysis"
        $findings[0].Expected | Should -Be 1
        $findings[0].Actual | Should -BeNullOrEmpty
        $findings[0].Message | Should -Match "missing"
    }

    It "detects a policy value that is no longer the off value" {
        $values = Get-CleanPolicyValues
        $values["HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsAI|AllowRecallEnablement"] = 1
        $findings = @(Get-WindowsAIFindings -GetPolicyValue (New-PolicyReader -Values $values) -GetCopilotPackages { @() })
        $findings.Count | Should -Be 1
        $findings[0].Name | Should -Be "AllowRecallEnablement"
        $findings[0].Expected | Should -Be 0
        $findings[0].Actual | Should -Be 1
    }

    It "detects an installed Microsoft.Copilot package and ignores other packages" {
        $listed = @(
            [pscustomobject]@{ Name = "Microsoft.Copilot"; PackageFullName = "Microsoft.Copilot_1.0.0.0_neutral" }
            [pscustomobject]@{ Name = "Microsoft.WindowsNotepad" }
        )
        $packages = @(Get-WindowsAIInstalledCopilotPackages -ListPackages { $listed }.GetNewClosure())
        $packages.Count | Should -Be 1
        $packages[0].Name | Should -Be "Microsoft.Copilot"

        $findings = @(Get-WindowsAIFindings -GetPolicyValue (New-PolicyReader -Values (Get-CleanPolicyValues)) -GetCopilotPackages { $packages })
        $findings.Count | Should -Be 1
        $findings[0].Kind | Should -Be "App"
        $findings[0].Name | Should -Be "Microsoft.Copilot"
    }

    It "does not treat a null package list as Copilot being installed" {
        $findings = @(Get-WindowsAIFindings -GetPolicyValue (New-PolicyReader -Values (Get-CleanPolicyValues)) -GetCopilotPackages { $null })
        $findings.Count | Should -Be 0
    }

    It "reports a registry read error without inventing a value" {
        $reader = {
            param($Path, $Name)
            if ($Name -eq "ShowCopilotButton") {
                throw "registry unavailable"
            }
            $map = Get-CleanPolicyValues
            return $map["$Path|$Name"]
        }
        $findings = @(Get-WindowsAIFindings -GetPolicyValue $reader -GetCopilotPackages { @() })
        $findings.Count | Should -Be 1
        $findings[0].Kind | Should -Be "ReadError"
        $findings[0].Name | Should -Be "ShowCopilotButton"
    }
}

Describe "when to notify" {
    BeforeAll {
        $script:SampleFinding = [pscustomobject]@{
            Kind = "Policy"
            Path = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsAI"
            Name = "DisableClickToDo"
            Expected = 1
            Actual = $null
            Message = "missing"
        }
        $script:Now = [datetime]::Parse("2026-06-01T12:00:00Z")
    }

    It "stays quiet when the user restored Windows AI on purpose" {
        $decision = Get-WindowsAIWatchDecision -Findings @($script:SampleFinding) -UserRestored $true -NowUtc $script:Now -CooldownHours 0
        $decision.ShouldNotify | Should -BeFalse
        $decision.ExitCode | Should -Be 0
        $decision.Reason | Should -Be "UserRestored"
        @($decision.Findings).Count | Should -Be 1
    }

    It "notifies on a manual check as soon as drift is present" {
        $decision = Get-WindowsAIWatchDecision -Findings @($script:SampleFinding) -UserRestored $false -NowUtc $script:Now -CooldownHours 0
        $decision.ShouldNotify | Should -BeTrue
        $decision.ExitCode | Should -Be 2
        $decision.Reason | Should -Be "Drift"
    }

    It "suppresses the same update result inside the 3 hour burst window" {
        $fingerprint = Get-WindowsAIFindingFingerprint -Findings @($script:SampleFinding)
        $decision = Get-WindowsAIWatchDecision `
            -Findings @($script:SampleFinding) `
            -UserRestored $false `
            -NowUtc $script:Now `
            -LastFingerprint $fingerprint `
            -LastNotifiedUtc $script:Now.AddHours(-2) `
            -CooldownHours (Get-WindowsAIWatcherCooldownHours -Source "Update")
        $decision.ShouldNotify | Should -BeFalse
        $decision.Reason | Should -Be "Cooldown"
        $decision.ExitCode | Should -Be 2
    }

    It "notifies again from the update task after the burst window" {
        $fingerprint = Get-WindowsAIFindingFingerprint -Findings @($script:SampleFinding)
        $decision = Get-WindowsAIWatchDecision `
            -Findings @($script:SampleFinding) `
            -UserRestored $false `
            -NowUtc $script:Now `
            -LastFingerprint $fingerprint `
            -LastNotifiedUtc $script:Now.AddHours(-4) `
            -CooldownHours (Get-WindowsAIWatcherCooldownHours -Source "Update")
        $decision.ShouldNotify | Should -BeTrue
        $decision.Reason | Should -Be "Drift"
    }

    It "keeps sign-in and daily reminders on the longer cooldown" {
        (Get-WindowsAIWatcherCooldownHours -Source "Logon") | Should -Be 20
        (Get-WindowsAIWatcherCooldownHours -Source "Daily") | Should -Be 20
        (Get-WindowsAIWatcherCooldownHours -Source "Manual") | Should -Be 0

        $fingerprint = Get-WindowsAIFindingFingerprint -Findings @($script:SampleFinding)
        $decision = Get-WindowsAIWatchDecision `
            -Findings @($script:SampleFinding) `
            -UserRestored $false `
            -NowUtc $script:Now `
            -LastFingerprint $fingerprint `
            -LastNotifiedUtc $script:Now.AddHours(-4) `
            -CooldownHours (Get-WindowsAIWatcherCooldownHours -Source "Daily")
        $decision.ShouldNotify | Should -BeFalse
        $decision.Reason | Should -Be "Cooldown"
    }

    It "notifies immediately when the drifted set changes" {
        $old = Get-WindowsAIFindingFingerprint -Findings @($script:SampleFinding)
        $changed = [pscustomobject]@{
            Kind = "App"
            Path = "AppX"
            Name = "Microsoft.Copilot"
            Expected = "NotInstalled"
            Actual = 1
            Message = "installed"
        }
        $decision = Get-WindowsAIWatchDecision `
            -Findings @($script:SampleFinding, $changed) `
            -UserRestored $false `
            -NowUtc $script:Now `
            -LastFingerprint $old `
            -LastNotifiedUtc $script:Now.AddMinutes(-5) `
            -CooldownHours 20
        $decision.ShouldNotify | Should -BeTrue
        $decision.Reason | Should -Be "Drift"
    }
}

Describe "one-click reapply" {
    It "starts UpgradeWithoutAI.bat and does not pass policy values" {
        $before = Get-Content -LiteralPath (Join-Path $script:RepoRoot "Disable-WindowsAI.ps1") -Raw
        $started = $null
        $cmd = Invoke-WindowsAIReapply -ScriptRoot $script:RepoRoot -Start {
            param($FilePath, $ArgumentList)
            $script:StartedReapply = [pscustomobject]@{
                FilePath = $FilePath
                ArgumentList = @($ArgumentList)
            }
        }
        $cmd.FilePath | Should -Be (Join-Path $script:RepoRoot "UpgradeWithoutAI.bat")
        @($cmd.ArgumentList).Count | Should -Be 0
        $script:StartedReapply.FilePath | Should -Be $cmd.FilePath
        ($script:StartedReapply.ArgumentList -join " ") | Should -Not -Match "AllowRecallEnablement"
        ($script:StartedReapply.ArgumentList -join " ") | Should -Not -Match "Set-Dword"
        (Get-Content -LiteralPath (Join-Path $script:RepoRoot "Disable-WindowsAI.ps1") -Raw) | Should -Be $before
    }

    It "falls back to Disable-WindowsAI.ps1 without embedding policy values" {
        $temp = Join-Path ([System.IO.Path]::GetTempPath()) ("uwa-" + [guid]::NewGuid().ToString("n"))
        New-Item -ItemType Directory -Path $temp | Out-Null
        try {
            Set-Content -LiteralPath (Join-Path $temp "Disable-WindowsAI.ps1") -Value "# placeholder" -Encoding UTF8
            $cmd = Get-WindowsAIReapplyCommand -ScriptRoot $temp
            $cmd.FilePath | Should -Be "powershell.exe"
            $joined = $cmd.ArgumentList -join " "
            $joined | Should -Match "Disable-WindowsAI\.ps1"
            $joined | Should -Not -Match "AllowRecallEnablement"
            $joined | Should -Not -Match "DisableAIDataAnalysis"
            $joined | Should -Not -Match "TurnOffWindowsCopilot"
        } finally {
            Remove-Item -LiteralPath $temp -Recurse -Force
        }
    }

    It "invokes reapply when the user accepts, and skips it when they decline" {
        $missing = { param($Path, $Name) $null }
        $accepted = Invoke-WatchForTest -GetPolicyValue $missing -Prompt { param($Findings) "Yes" }
        $accepted.ShouldNotify | Should -BeTrue
        $accepted.ExitCode | Should -Be 2
        $script:TestWatch.Prompted | Should -BeTrue
        $script:TestWatch.ReapplyRoot | Should -Be $script:RepoRoot
        $script:TestWatch.StateWrites.Count | Should -Be 1

        $declined = Invoke-WatchForTest -GetPolicyValue $missing -Prompt { param($Findings) "No" }
        $declined.ShouldNotify | Should -BeTrue
        $script:TestWatch.ReapplyRoot | Should -BeNullOrEmpty
        $script:TestWatch.StateWrites.Count | Should -Be 1
    }

    It "does not notify or reapply when the machine is already clean" {
        $decision = Invoke-WatchForTest -GetPolicyValue (New-PolicyReader -Values (Get-CleanPolicyValues)) -Prompt { param($Findings) throw "prompt should not run" }
        $decision.Reason | Should -Be "Clean"
        $decision.ShouldNotify | Should -BeFalse
        $script:TestWatch.Prompted | Should -BeFalse
        $script:TestWatch.ReapplyRoot | Should -BeNullOrEmpty
        $script:TestWatch.StateWrites.Count | Should -Be 1
        $script:TestWatch.StateWrites[0].Fingerprint | Should -BeNullOrEmpty
    }

    It "does not nag after Restore-WindowsAI even if values are missing" {
        $decision = Invoke-WatchForTest -GetPolicyValue { param($Path, $Name) $null } -UserRestored $true -Prompt { param($Findings) throw "prompt should not run" }
        $decision.Reason | Should -Be "UserRestored"
        $decision.ExitCode | Should -Be 0
        $script:TestWatch.Prompted | Should -BeFalse
        $script:TestWatch.ReapplyRoot | Should -BeNullOrEmpty
        $script:TestWatch.StateWrites.Count | Should -Be 1
        $script:TestWatch.StateWrites[0].Fingerprint | Should -BeNullOrEmpty
    }

    It "does not prompt during cooldown, and a quiet run does not start reapply" {
        $missing = { param($Path, $Name) $null }
        $first = Invoke-WatchForTest -GetPolicyValue $missing -Source "Update" -Prompt { param($Findings) "No" }
        $fingerprint = $first.Fingerprint
        $state = [pscustomobject]@{
            Fingerprint = $fingerprint
            LastNotifiedUtc = ([datetime]::Parse("2026-06-01T12:00:00Z")).AddHours(-1).ToString("o")
        }
        $second = Invoke-WatchForTest -GetPolicyValue $missing -Source "Update" -State $state -Prompt { param($Findings) throw "prompt should not run" }
        $second.Reason | Should -Be "Cooldown"
        $second.ShouldNotify | Should -BeFalse
        $script:TestWatch.Prompted | Should -BeFalse

        $quiet = Invoke-WatchForTest -GetPolicyValue $missing -Quiet -Prompt { param($Findings) throw "prompt should not run" }
        $quiet.ShouldNotify | Should -BeTrue
        $script:TestWatch.Prompted | Should -BeFalse
        $script:TestWatch.ReapplyRoot | Should -BeNullOrEmpty
    }
}

Describe "prompt text" {
    It "offers the existing disable path and does not claim Phi Silica or OneDrive are removed" {
        $text = Get-WindowsAIDriftPromptText -Findings @([pscustomobject]@{ Message = "example drift" })
        $text | Should -Match "Upgrade without AI"
        $text | Should -Match "Defender"
        $text | Should -Match "Windows Update"
        $text | Should -Match "Phi Silica"
        $text | Should -Match "OneDrive Summarize"
        $text | Should -Match "Click Yes"
        $text | Should -Match "Restore Windows AI"
        $text | Should -Match "example drift"
        $text | Should -Not -Match "Phi Silica is removed"
        $text | Should -Not -Match "removed Phi Silica"
    }
}

Describe "scheduled task definition" {
    It "prioritizes Windows Update event 19 and keeps sign-in and daily fallbacks" {
        $tasks = @(Get-WindowsAIWatcherTaskDefinition -ScriptRoot $script:RepoRoot)
        $tasks.Count | Should -Be 3

        $update = @($tasks | Where-Object { $_.TaskName -eq "WatchAfterUpdate" })[0]
        $logon = @($tasks | Where-Object { $_.TaskName -eq "WatchAtLogon" })[0]
        $daily = @($tasks | Where-Object { $_.TaskName -eq "WatchDaily" })[0]

        $update.TaskPath | Should -Be "\UpgradeWithoutAI\"
        $update.Source | Should -Be "Update"
        $update.Trigger.Kind | Should -Be "WindowsUpdateInstalled"
        $update.Trigger.LogName | Should -Be "Microsoft-Windows-WindowsUpdateClient/Operational"
        $update.Trigger.Provider | Should -Be "Microsoft-Windows-WindowsUpdateClient"
        $update.Trigger.EventId | Should -Be 19
        $update.Trigger.DelayMinutes | Should -Be 3
        $update.Arguments | Should -Match "Watch-WindowsAI\.ps1"
        $update.Arguments | Should -Match "-Source Update"
        $update.Arguments | Should -Not -Match "Disable-WindowsAI"

        $query = Get-WindowsAIUpdateEventQuery -LogName $update.Trigger.LogName -Provider $update.Trigger.Provider -EventId $update.Trigger.EventId
        $query.Contains("EventID=19") | Should -BeTrue
        $query.Contains("Microsoft-Windows-WindowsUpdateClient/Operational") | Should -BeTrue
        $query.Contains("Provider[@Name='Microsoft-Windows-WindowsUpdateClient']") | Should -BeTrue

        $logon.Trigger.Kind | Should -Be "Logon"
        $logon.Trigger.DelayMinutes | Should -Be 2
        $logon.Arguments | Should -Match "-Source Logon"

        $daily.Trigger.Kind | Should -Be "Daily"
        $daily.Trigger.At | Should -Be "09:15"
        $daily.Arguments | Should -Match "-Source Daily"

        $installer = Get-Content -LiteralPath (Join-Path $script:RepoRoot "Install-WindowsAIWatcher.ps1") -Raw
        $installer | Should -Match "Get-WindowsAIWatcherTaskDefinition"
        $installer | Should -Match "Unregister-ScheduledTask"
        $installer | Should -Not -Match "Set-Dword"
        $installer | Should -Not -Match "AllowRecallEnablement"
    }
}

Describe "user restored marker" {
    It "uses one marker name in the disable script, the restore script, and the watcher" {
        $name = Get-WindowsAIUserRestoredMarkerName
        $name | Should -Be "user-restored.marker"
        $path = Get-WindowsAIUserRestoredMarkerPath -ProgramDataRoot "C:\ProgramData"
        $path | Should -Be "C:\ProgramData\UpgradeWithoutAI\user-restored.marker"

        $disable = Get-Content -LiteralPath (Join-Path $script:RepoRoot "Disable-WindowsAI.ps1") -Raw
        $restore = Get-Content -LiteralPath (Join-Path $script:RepoRoot "Restore-WindowsAI.ps1") -Raw
        $disable.Contains($name) | Should -BeTrue
        $disable.Contains('Remove-Item $restoredMarker') | Should -BeTrue
        $restore.Contains($name) | Should -BeTrue
        $restore.Contains('Set-Content -Path $restoredMarker') | Should -BeTrue
    }
}

Describe "watcher state" {
    It "round-trips the last notification and clears it when the fingerprint is empty" {
        $old = $env:LOCALAPPDATA
        $temp = Join-Path ([System.IO.Path]::GetTempPath()) ("uwa-state-" + [guid]::NewGuid().ToString("n"))
        try {
            New-Item -ItemType Directory -Path $temp | Out-Null
            $env:LOCALAPPDATA = $temp
            $when = [datetime]::Parse("2026-06-01T12:00:00Z")
            Write-WindowsAIWatcherState -Fingerprint "abc" -LastNotifiedUtc $when
            $state = Read-WindowsAIWatcherState
            $state.Fingerprint | Should -Be "abc"
            ([datetime]$state.LastNotifiedUtc).ToUniversalTime() | Should -Be $when.ToUniversalTime()

            Write-WindowsAIWatcherState -Fingerprint "" -LastNotifiedUtc $null
            (Test-Path -LiteralPath (Get-WindowsAIWatcherStatePath)) | Should -BeFalse
            Read-WindowsAIWatcherState | Should -BeNullOrEmpty
        } finally {
            $env:LOCALAPPDATA = $old
            if (Test-Path -LiteralPath $temp) {
                Remove-Item -LiteralPath $temp -Recurse -Force
            }
        }
    }
}

Describe "script files parse" {
    It "parses the watcher and installer, and dot-sourcing the watcher does not run a check" {
        $files = @(
            "WindowsAI.Common.ps1"
            "Watch-WindowsAI.ps1"
            "Install-WindowsAIWatcher.ps1"
            "Disable-WindowsAI.ps1"
            "Restore-WindowsAI.ps1"
        )
        foreach ($file in $files) {
            $errors = $null
            $tokens = $null
            [void][System.Management.Automation.Language.Parser]::ParseFile((Join-Path $script:RepoRoot $file), [ref]$tokens, [ref]$errors)
            @($errors).Count | Should -Be 0
        }

        . (Join-Path $script:RepoRoot "Watch-WindowsAI.ps1")
        Get-Command Show-WindowsAIDriftPrompt | Should -Not -BeNullOrEmpty
    }
}
