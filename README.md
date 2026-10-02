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

Windows Update can turn these AI features back on, or install the Copilot app again.

1. Double-click `InstallWindowsAIWatcher.bat`. That step does not ask for admin approval.
2. Leave this folder where it is. If you move it, run the installer again.

The check runs after Windows finishes an update, when you sign in, and once a day if those did not run. It does not turn off Defender or Windows Update. It does not remove Phi Silica or OneDrive Summarize.

You only see a message when something this tool turns off is back on. Click **Yes** to run `UpgradeWithoutAI.bat` again. Windows asks for administrator approval only then. Click **No** and the same reminder waits until the next day.

A burst of update notices only checks once. Signing in after an update still checks, because a restart can bring features back. The daily check does nothing if a check already ran in the last 12 hours.

`RestoreWindowsAI.bat` stops the reminders until you turn AI off again. It writes `C:\ProgramData\UpgradeWithoutAI\user-restored.marker`. Turning AI off again deletes that file.

On Home, some settings never stay off. You may see the same reminder after updates. Double-click `UninstallWindowsAIWatcher.bat` if you do not want it.

To check now, double-click `CheckWindowsAI.bat`. The window says whether anything this tool turns off is back on. Nothing to report exits 0. Something back on exits 2. The log is `%LOCALAPPDATA%\UpgradeWithoutAI\watcher.log`.

The check looks at your signed-in account. It does not ask for admin approval to look. Yes on the message is what runs the full turn-off script.

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
