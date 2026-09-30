@echo off
setlocal
set "SCRIPT=%~dp0CATIA-LargeAssembly-Profile.ps1"
if exist "%SCRIPT%" goto :run

powershell.exe -NoProfile -WindowStyle Hidden -Command "Add-Type -AssemblyName System.Windows.Forms; [System.Windows.Forms.MessageBox]::Show('Application file was not found. Keep CATIA-LargeAssembly-Profile.ps1 next to this launcher.','CATIA Large Assembly Profile','OK','Error') | Out-Null"
exit /b 1

:run
powershell.exe -NoProfile -ExecutionPolicy RemoteSigned -WindowStyle Hidden -File "%SCRIPT%"
if errorlevel 1 powershell.exe -NoProfile -WindowStyle Hidden -Command "Add-Type -AssemblyName System.Windows.Forms; [System.Windows.Forms.MessageBox]::Show('Application could not start. Verify the script signature or use a trusted local copy.','CATIA Large Assembly Profile','OK','Error') | Out-Null"
endlocal
