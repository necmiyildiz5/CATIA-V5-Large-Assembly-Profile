# Security notes

This tool is intentionally local-only: it does not download content, open network connections, upload CATIA files, or send telemetry.

## Write boundaries

The app accepts only:

- a source `.txt` or `.CATEnv` file from the detected Dassault `CATEnv` folders;
- the current user's `%APPDATA%\DassaultSystemes\CATEnv` folder as the new environment target;
- a `CATSettings_...` subfolder under `%APPDATA%\DassaultSystemes` as the settings target;
- `CATSTART.exe` under `%ProgramFiles%\Dassault Systemes`.

It rejects invalid profile names, paths containing quotes, source files above 2 MB, reparse-point/junction targets, non-CATIA source files, and executable paths outside the Dassault installation root. It never overwrites a profile that targets a different CATSettings folder.

## Before publishing

Do not commit or distribute a real CATEnv file, CATSettings directory, `licenses.CATSettings`, generated logs, generated macro, plan JSON, desktop shortcut, or any company/project data. Review `git status` before pushing.

For a release build, code-sign the `.ps1` or package it in a signed executable according to your organization's Windows code-signing policy. Do not disable PowerShell execution policy globally.
