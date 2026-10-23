@echo off
rem ---------------------------------------------------------------------------
rem  One-time setup: creates .venv and installs flask + python-snap7.
rem  Safe to re-run. A .venv copied from another PC (which cannot run here)
rem  is moved aside to .venv_broken and rebuilt.
rem
rem  Usage:  setup.bat            (pauses at the end)
rem          setup.bat quiet      (no pause; used by the start scripts)
rem ---------------------------------------------------------------------------
setlocal
cd /d "%~dp0"

echo.
echo   SCADA platform - setup
echo   ----------------------------------------------

rem --- 1. Is the existing venv usable on this PC? ---------------------------
if not exist ".venv\Scripts\python.exe" goto :find_python
.venv\Scripts\python.exe --version >nul 2>&1
if not errorlevel 1 goto :install

echo   Existing .venv was built on another PC and cannot run here.
echo   Moving it to .venv_broken and creating a fresh one.
if exist ".venv_broken" rmdir /s /q ".venv_broken"
move ".venv" ".venv_broken" >nul
if errorlevel 1 goto :move_failed

rem --- 2. Find a Python 3 interpreter ---------------------------------------
:find_python
set "PY="
py -3 --version >nul 2>&1 && set "PY=py -3"
if not defined PY python --version >nul 2>&1 && set "PY=python"
if not defined PY goto :no_python

for /f "delims=" %%v in ('%PY% --version 2^>^&1') do echo   Using %%v
echo   Creating .venv ...
%PY% -m venv .venv
if errorlevel 1 goto :venv_failed

rem --- 3. Install dependencies ----------------------------------------------
:install
echo   Installing requirements (flask, python-snap7) ...
.venv\Scripts\python.exe -m pip install --disable-pip-version-check -q -r requirements.txt
if errorlevel 1 goto :pip_failed

.venv\Scripts\python.exe -c "import flask, snap7" >nul 2>&1
if errorlevel 1 goto :pip_failed

echo   [OK] Setup complete.
echo.
if /i not "%~1"=="quiet" pause
exit /b 0

:no_python
echo   [FAIL] Python 3 not found.
echo          Install it from https://www.python.org/downloads/
echo          and tick "Add python.exe to PATH" during install.
goto :fail

:move_failed
echo   [FAIL] Could not move the old .venv. Close any program using it and retry.
goto :fail

:venv_failed
echo   [FAIL] Could not create the virtual environment.
goto :fail

:pip_failed
echo   [FAIL] pip install failed. Check the internet connection, or install
echo          offline from wheels:  .venv\Scripts\python.exe -m pip install --no-index --find-links WHEELS_DIR -r requirements.txt
goto :fail

:fail
echo.
if /i not "%~1"=="quiet" pause
exit /b 1
