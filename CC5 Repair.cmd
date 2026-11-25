@echo off
rem SPDX-License-Identifier: GPL-3.0-only
setlocal
pushd "%~dp0"
echo Character Creator 5 native opening repair
echo.
echo 1. Check installation
echo 2. Install repair   (run this menu as administrator)
echo 3. Remove repair    (run this menu as administrator)
echo 4. Exit
choice /c 1234 /n /m "Select 1-4: "
if errorlevel 4 goto finish
if errorlevel 3 (set "action=Uninstall") else if errorlevel 2 (set "action=Install") else (set "action=Check")
powershell.exe -NoProfile -ExecutionPolicy RemoteSigned -File "%~dp0Repair-CC5.ps1" "%action%"
if errorlevel 1 echo The operation did not complete. See the message above.
pause
:finish
popd
