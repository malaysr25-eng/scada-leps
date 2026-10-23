@echo off
rem ---------------------------------------------------------------------------
rem  Connect to the real PLC and start the SCADA dashboard.
rem
rem  Usage:  start_dashboard.bat               (asks for the PLC IP, Enter keeps it)
rem          start_dashboard.bat 172.21.30.157 (sets the IP, no prompt)
rem
rem  The IP is saved to config\config.json, so next time Enter is enough.
rem  Stop the dashboard with Ctrl+C in this window.
rem ---------------------------------------------------------------------------
setlocal
cd /d "%~dp0"
title SCADA Dashboard - PLC
set "VPY=.venv\Scripts\python.exe"

rem --- 1. Environment --------------------------------------------------------
%VPY% -c "import flask, snap7" >nul 2>&1
if errorlevel 1 call setup.bat quiet
if errorlevel 1 goto :fail

rem --- 2. PLC address --------------------------------------------------------
if not "%~1"=="" goto :set_from_arg

:ask_ip
for /f "delims=" %%i in ('%VPY% tools\plc_config.py get-ip') do set "CUR_IP=%%i"
echo.
set "NEW_IP="
set /p "NEW_IP=  PLC IP address [%CUR_IP%] (Enter to keep): "
if not defined NEW_IP goto :test
%VPY% tools\plc_config.py set-ip %NEW_IP%
if errorlevel 1 goto :ask_ip
goto :test

:set_from_arg
%VPY% tools\plc_config.py set-ip %~1
if errorlevel 1 goto :fail

rem --- 3. Pre-flight connection test -----------------------------------------
:test
echo.
%VPY% tools\plc_config.py test
if not errorlevel 1 goto :port_check
echo.
echo   The PLC did not answer. The dashboard reconnects on its own once the
echo   PLC is reachable, so it is safe to start anyway.
choice /c YN /m "  Start the dashboard anyway"
if errorlevel 2 goto :end

rem --- 4. Port check (the legacy apps also used 5000) ------------------------
:port_check
for /f "delims=" %%p in ('%VPY% tools\plc_config.py get-port') do set "PORT=%%p"
netstat -ano | findstr /r /c:":%PORT% .*LISTENING" >nul
if errorlevel 1 goto :run
echo.
echo   [WARN] Something is already listening on port %PORT%.
echo          Close the old dashboard (PLC_Dashboard\app.py etc.) first --
echo          it holds its own PLC connection and will compete with this one.
choice /c YN /m "  Continue anyway"
if errorlevel 2 goto :end

rem --- 5. Run ----------------------------------------------------------------
:run
echo.
echo   Dashboard on this PC   : http://127.0.0.1:%PORT%
%VPY% tools\plc_config.py lan-urls
echo.
start "" cmd /c "timeout /t 4 /nobreak >nul & start http://127.0.0.1:%PORT%"
%VPY% run.py
goto :end

:fail
echo.
echo   [FAIL] Could not start. See the messages above.
:end
echo.
pause
