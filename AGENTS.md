# Repository Conventions

- Keep scripts compatible with Windows PE/PowerShell 5 (no Unicode symbols, avoid modules that are not available in WinPE by default).
- Add a short `# DESC: ...` (or `:: DESC:` for batch files) at the top of any tool so it shows in the menu.
- Update `README.md` whenever you add or rename tools, entry points, or environment expectations.
- Prefer plain ASCII and 2-space indentation inside PowerShell scripts to match existing style.
- When you add a new tool, place it under `PROD/Tools/` and ensure it can run from `X:\Windows\System32\Tools` when booted into WinPE.
