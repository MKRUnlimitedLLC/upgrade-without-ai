# INTERNAL launch checklist

Maintainers only. This is not user documentation and not a release announcement. Do not copy it into the README, release notes, or scripts.

## Launch gate

- The launch channel is a GitHub Release only.
- v0.2.2 already counts as launched. Do not publish another release for this hardening pass.
- Do not soft-announce.
- Do not submit this tool to the Microsoft Store.
- Do not buy a domain.
- Do not spend money for this launch.
- Do not add pricing, a fee, or a paid flow to any public file. The README stays a free scan report.

## Product limits

- Documented disables only. Do not invent policy values.
- Do not disable Microsoft Defender.
- Do not disable Windows Update.
- Do not claim this tool removes Phi Silica.
- Do not claim this tool turns off or removes OneDrive Summarize. Windows has no Settings switch for Summarize alone, and this tool has no registry setting for it.

## Before you change public copy

- Run `pwsh -NoProfile -File ./tests/Run-Tests.ps1`.
- `InstallWindowsAIWatcher.bat` runs `Install-WindowsAIWatcher.ps1`.
- `UninstallWindowsAIWatcher.bat` runs `Install-WindowsAIWatcher.ps1 -Uninstall`.
- `UpgradeWithoutAI.bat` runs `Disable-WindowsAI.ps1`.
- `RestoreWindowsAI.bat` runs `Restore-WindowsAI.ps1`.
- `CheckWindowsAI.bat` runs `Watch-WindowsAI.ps1 -Source Manual`.
- The manual Settings guide still covers File Explorer AI actions, Experimental agentic features, and OneDrive Summarize.
