@echo off
rem ---------------------------------------------------------------------------
rem  Start the dashboard with NO PLC (in-memory simulator). For demos and
rem  checking the UI on a PC that is not on the PLC network.
rem  Extra arguments go to run.py, e.g.:  start_simulator.bat --sim-fault emergency
rem ---------------------------------------------------------------------------
setlocal
cd /d "%~dp0"
title SCADA Dashboard - SIMULATOR
set "VPY=.venv\Scripts\python.exe"

%VPY% -c "import flask, snap7" >nul 2>&1
if errorlevel 1 call setup.bat quiet
if errorlevel 1 goto :fail

for /f "delims=" %%p in ('%VPY% tools\plc_config.py get-port') do set "PORT=%%p"
start "" cmd /c "timeout /t 4 /nobreak >nul & start http://127.0.0.1:%PORT%"
%VPY% run.py --simulate %*
goto :end

:fail
echo   [FAIL] Setup did not complete. See the messages above.
:end
echo.
pause
