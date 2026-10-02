# Upgrade without AI

Double-click tool that turns off the Windows 11 AI features Microsoft actually exposes to policy: Recall snapshots, Click to Do, the Settings agent, Paint generative tools, and the Copilot app and taskbar button.

It does not delete Windows, disable Defender, or block updates. It also cannot remove on-device Copilot+ models such as Phi Silica, and it cannot stop OneDrive cloud summarization while you stay signed into Microsoft 365 Copilot.

Tested against Microsoft's WindowsAI policy CSP as published for Windows 11 24H2 and later, including the 26H2 (2026 Update) servicing branch. Home may ignore some policy values; app removal still runs.

Home is MKR Connect LLC, an incubator project of MKR-UNLIMITED LLC. Not its own company.

## Use it

1. Download this folder, or clone the repo.
2. Double-click `UpgradeWithoutAI.bat`.
3. Approve the Windows admin prompt.
4. Read the summary. Restart when it asks.

To undo: double-click `RestoreWindowsAI.bat`, then restart. That also tells the post-update watcher to stay quiet until you apply this tool again.

A log and per-key registry backups are written to `C:\ProgramData\UpgradeWithoutAI`. The script reads every policy value back before it reports success. If a write does not stick, the window stays open and the exit code is 1.

Sign out or restart after it finishes. It does not restart Explorer. Restarting Explorer from the admin prompt can leave the shell running as administrator.

## After Windows Update

Windows Update can put these policy values back to defaults, or install the Copilot store app again. The watcher reads the same values `Disable-WindowsAI.ps1` writes. It also checks whether `Microsoft.Copilot` is installed. It does not turn updates or Defender off, and it does not remove Phi Silica or OneDrive Summarize.

1. Double-click `InstallWindowsAIWatcher.bat`.
2. Leave this folder where it is. The tasks point at this copy of `Watch-WindowsAI.ps1`. Run the installer again if you move the folder.

The tasks run in your signed-in session, not as admin. They can read your policy values. Copilot is checked for all users when Windows allows that without admin, and otherwise for your user. Clicking **Yes** on the prompt runs `UpgradeWithoutAI.bat`, which is the same admin prompt as a manual run.

Triggers:

- **Windows Update finished.** Event 19, "Installation successful," in `Microsoft-Windows-WindowsUpdateClient/Operational`. The task waits 3 minutes. This is the post-update check. One update can write event 19 several times, so the same result prompts at most once every 3 hours.
- **Sign-in**, after 2 minutes. A feature update often reboots, and the event can also fire while you are signed out. A prompt needs your session, so sign-in covers that.
- **Daily at 9:15** local time, with up to 30 minutes of random delay. This runs when the event trigger does not. Sign-in and daily checks repeat the same result only after 20 hours. A new difference prompts right away.

Click **No** to be reminded later. That is not the same as turning the features back on. `RestoreWindowsAI.bat` writes `C:\ProgramData\UpgradeWithoutAI\user-restored.marker`. While that file exists, the watcher does not prompt. `UpgradeWithoutAI.bat` deletes the marker when it applies the policies again.

On Home, some policy values never stick. The watcher will keep seeing those as drifted. Uninstall it if that reminder is not useful.

Remove the tasks with `UninstallWindowsAIWatcher.bat`. To check once yourself, double-click `CheckWindowsAI.bat`. A clean check exits 0. Drift exits 2. The log is `%LOCALAPPDATA%\UpgradeWithoutAI\watcher.log`.

If the event trigger cannot be registered, the installer still adds the sign-in and daily tasks and says so.

## What it changes

| Feature | What the script does |
| --- | --- |
| Recall | Policy: not available, snapshots off. Removes the optional Windows feature when it is present. |
| Click to Do | Policy disable. |
| Settings agent | Policy disable. |
| Paint Cocreator, Generative fill, Image Creator | Policy disable. |
| Copilot button | Hidden for the current user. |
| Copilot app | Uninstalled for existing users and deprovisioned so new users do not get it. |
| Copilot policy | `TurnOffWindowsCopilot` and `RemoveMicrosoftCopilotApp` set. The removal policy has a 28-day inactivity rule and does not cover every edition. The script uninstalls the app immediately instead of waiting. |

## What a script cannot honestly switch off

- Phi Silica and the other Copilot+ AI components. Settings only lets you uninstall the image-generation model, and that control is not a stable script target.
- File Explorer "AI actions" and OneDrive Summarize. Those are app actions and a cloud Microsoft 365 feature. Turn them off in Settings, Apps, Actions, or do not use the OneDrive submenu.
- Experimental agentic features, if you already turned them on. That toggle is Settings, System, AI components. It is off unless someone enabled it.
- Windows settings backup on an Entra-joined work PC. That is an admin policy.

## Requirements

Windows 11 24H2 or newer. An administrator account. Pro, Enterprise, and Education honor the policy keys. Home gets the app removal, the taskbar hide, and the Recall feature removal when those pieces exist.

## Tests

The checks are Pester tests. They mock registry and AppX reads. They do not need a Windows Update, and they do not change the policy values in `Disable-WindowsAI.ps1`.

With PowerShell 7:

```
pwsh -NoProfile -File ./tests/Run-Tests.ps1
```

That installs Pester 5 for the current user if it is missing, then runs `Invoke-Pester` on `./tests`. GitHub Actions runs the same script.

## License

MIT. See LICENSE.
