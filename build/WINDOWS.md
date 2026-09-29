# Building and installing Wellformed on Windows

## A. Build (once, on any Windows PC you can install Julia on)
1. Install Julia 1.12: in PowerShell, `winget install --id Julialang.Juliaup` then `juliaup add 1.12`
   and `juliaup default 1.12`. Open a new PowerShell window afterwards.
2. Get this repository onto the machine (git clone, or copy the folder).
3. From the repository folder: `julia build\build_app.jl`
   (10-30 minutes; it downloads dependencies and compiles a private copy of Julia).
4. Result: `dist\wellformed\` (a few hundred MB). The program is `dist\wellformed\bin\Wellformed.exe`.

## B. Install on the instrument PC (no Julia needed)
1. Copy the whole `dist\wellformed` folder to e.g. `C:\Wellformed\`.
2. Double-click `C:\Wellformed\bin\Wellformed.exe`. First run opens setup: pick the export
   folder, paste the Basecamp chatbot URL, and it sends a test alert.
3. To start it at login: run `Wellformed.exe --install-startup` (or answer Yes during setup).
   Undo with `--uninstall-startup`.

## C. Checks to do on the instrument PC
- `Wellformed.exe --check some_export.xlsx` reports OK.
- Copy a truncated file into the export folder: popup appears on top of the instrument software
  and a Basecamp line is posted.
- Log off/on: Wellformed starts by itself (a minimized window in the taskbar).
- Antivirus/SmartScreen may warn about an unsigned exe the first time; note the message if so.
