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
- Copilot key remap stays guide-only. Do not invent a policy or registry value that remaps the key to Right Ctrl or Context Menu. Do not write SetCopilotHardwareKey.
- Do not claim Voice access natural-language commanding is turned off. No documented disable policy was found on 2026-10-05.
- AI component version stays "not checked" unless a documented query for the installed version exists. Do not report 1.2608.951.0 as a version this tool read.
- Do not add ConfigureAgentConnectors, AgentConsentDuration, AgentConnectorAccessPolicy, or OnDeviceRegistryLoggingLevel as writes from the 2026-10-05 diff.

## Before you change public copy

- Run `pwsh -NoProfile -File ./tests/Run-Tests.ps1`.
- `InstallWindowsAIWatcher.bat` runs `Install-WindowsAIWatcher.ps1`.
- `UninstallWindowsAIWatcher.bat` runs `Install-WindowsAIWatcher.ps1 -Uninstall`.
- `UpgradeWithoutAI.bat` runs `Disable-WindowsAI.ps1`.
- `RestoreWindowsAI.bat` runs `Restore-WindowsAI.ps1`.
- `CheckWindowsAI.bat` runs `Watch-WindowsAI.ps1 -Source Manual`.
- The manual Settings guide still covers File Explorer AI actions, Experimental agentic features, OneDrive Summarize, and the Copilot key remap path.
