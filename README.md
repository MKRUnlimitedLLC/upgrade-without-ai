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

To check now, double-click `CheckWindowsAI.bat`. The window says whether anything this tool turns off is back on, then lists the items you still turn on or off yourself. Nothing to report exits 0. Something back on exits 2. The log is `%LOCALAPPDATA%\UpgradeWithoutAI\watcher.log`.

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

## Still manual

These are on or off only when you do it. The check and `UpgradeWithoutAI.bat` print the same guide. This tool does not remove Phi Silica, and it does not have a registry setting for OneDrive Summarize.

### File Explorer AI actions

When this is on, right-clicking a file in File Explorer can offer an AI action, such as editing a photo or summarizing a document, without opening the file first.

Turn off:

1. Press Windows+I to open Settings.
2. Select Apps, then Actions.
3. Turn off each action you do not want. If every action is off, File Explorer stops offering those AI actions.

Turn on:

1. Press Windows+I to open Settings.
2. Select Apps, then Actions.
3. Turn on the actions you want. They come back when you right-click a file those actions support.

### Experimental agentic features

When this is on, an agent such as Copilot Actions can work in its own window and use your apps and common folders, such as Documents and Desktop, while you keep using the PC. It stays off unless an administrator turns it on, and then it is on for every account on the PC.

Turn off:

1. Press Windows+I to open Settings.
2. Select System, then AI components.
3. Turn off Experimental agentic features.

Turn on:

1. Sign in with an administrator account.
2. Press Windows+I to open Settings.
3. Select System, then AI components.
4. Turn on Experimental agentic features. If Windows asks you to confirm, choose Turn on.

### OneDrive Summarize

When you are signed in with Microsoft 365 Copilot, OneDrive can write a short summary of a Word, Excel, PowerPoint, or PDF file. You ask for it from the Copilot button or the OneDrive menu. Windows has no Settings switch for Summarize alone, and this tool does not have a registry setting that turns it off.

Turn off:

1. Do not choose Summarize or Summarize this file in OneDrive or File Explorer.
2. Sign out of the Microsoft 365 Copilot account if you do not want those summaries offered. They stay available while that account is signed in.
3. On a work or school account, an administrator can turn off Copilot for OneDrive and SharePoint in the Microsoft 365 admin center. That is not a switch in Windows Settings.

Turn on:

1. Sign in to OneDrive with the Microsoft 365 account that includes Copilot.
2. Select a supported file, open Copilot or the OneDrive menu, and choose Summarize.

### Phi Silica and other on-device models

Phi Silica is a language model that runs on the PC for some Copilot+ features. This tool does not remove Phi Silica. Other on-device pieces, such as image generation, may show up on the same Settings page. Some of them are part of Windows and have no Uninstall button.

Turn off:

1. Press Windows+I to open Settings.
2. Select System, then AI components.
3. If a downloaded model shows Uninstall, you can uninstall that model yourself and restart. If Phi Silica has no Uninstall button, Windows is keeping that model and this tool cannot remove it.

Turn on:

1. Press Windows+I to open Settings.
2. Select System, then AI components.
3. If Windows shows an install button for a model you removed, use that button. If there is no button, Windows manages the model and this tool cannot turn it back on.

### Windows settings backup on a work PC

On a work PC signed in with Microsoft Entra, Windows can save your settings and put them on another PC. When that backup is on, a new PC can come back with the old preferences. An administrator decides whether backup is allowed. This tool does not change that policy.

Turn off:

1. Press Windows+I to open Settings.
2. Select Accounts, then Windows backup.
3. Turn off Remember my preferences if the switch is there. If the switch is missing or grayed out, your administrator controls it.

Turn on:

1. Press Windows+I to open Settings.
2. Select Accounts, then Windows backup.
3. Turn on Remember my preferences if Windows lets you. If the switch is missing, ask your administrator.

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
