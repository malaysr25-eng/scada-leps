@echo off
rem ---------------------------------------------------------------------------
rem  Check the PLC connection without starting the dashboard.
rem  Usage:  test_plc.bat              (uses the IP in config\config.json)
rem          test_plc.bat 172.21.30.157 (tests that IP, does not save it)
rem  Do not run while the dashboard is running.
rem ---------------------------------------------------------------------------
setlocal
cd /d "%~dp0"
set "VPY=.venv\Scripts\python.exe"

%VPY% -c "import flask, snap7" >nul 2>&1
if errorlevel 1 call setup.bat quiet
if errorlevel 1 goto :end

echo.
%VPY% tools\plc_config.py test %1

:end
echo.
pause
