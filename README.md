# Local User Move (WinPE Toolkit)

This toolkit boots a Windows PE image and exposes a simple menu for techs to unlock BitLocker volumes, deploy tooling, and move user data between machines or onto external drives. All scripts are designed to run from the PE environment without extra dependencies.

## Repository Layout
- `PROD/startnet.cmd` – Entry point invoked by WinPE after `wpeinit`; launches the PowerShell menu.
- `PROD/Menu/Menu.ps1` – ASCII-only menu that discovers tools under `X:\Windows\System32\Tools` and launches them (PowerShell, CMD, EXE, or built-ins like DiskPart and reboot/shutdown shortcuts).
- `PROD/Tools/` – Drop-in tools surfaced by the menu. Each script can include a `# DESC:`/`:: DESC:` line to show a description.
  - `MOVEME_To_External_Drive.ps1` – Guides copying user data from the local PC to an external destination.
  - `MOVEME_To_PC.ps1` – Mirrors the move workflow to another PC/volume.
  - `Manual_User_Move.cmd` – Batch fallback for manual transfers.
  - `Unlock_BDE.ps1` – Assists with unlocking BitLocker volumes via password or recovery key.

## Using the Toolkit in WinPE
1. Build or mount your WinPE image and copy the contents of `PROD/` to `X:\Windows\System32` (or the equivalent staging directory for your build process). The folder structure should end up as:
   - `X:\Windows\System32\startnet.cmd`
   - `X:\Windows\System32\Menu\Menu.ps1`
   - `X:\Windows\System32\Tools\` (containing the tool scripts)
2. Boot into WinPE. `startnet.cmd` runs automatically after `wpeinit`, widens the console, and launches the menu.
3. From the menu, select the tool number you want to run. Built-ins like **DiskPart**, **Reboot**, and **Shutdown** are always available.
4. After a tool finishes, press **ENTER** to return to the menu. Exiting the menu drops you to a standard WinPE command prompt.

## Adding New Tools
- Place new scripts in `PROD/Tools/` and ensure they run correctly when the toolkit is located at `X:\Windows\System32`.
- Add a one-line description at the top of the script (e.g., `# DESC: Capture event logs`) so it appears in the menu.
- Keep scripts compatible with PowerShell 5/WinPE: avoid non-ASCII characters and external module dependencies.
- Update this README with any new workflows, prerequisites, or required directory layouts.
