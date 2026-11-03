@echo off
setlocal
rem Run from any folder. All generated simulation files stay in AI_workspace.
set "SIM_SCRIPT=%~dp0..\..\..\AI_workspace\run.ps1"
set "SIM_RTL="
set "SIM_GUI="
set "SIM_PAUSE=1"
:args
if "%~1"=="" goto environment
if /i "%~1"=="--rtl" (
    set "SIM_RTL=-UseRtl"
) else if /i "%~1"=="--gui" (
    set "SIM_GUI=-Gui"
) else if /i "%~1"=="/nopause" (
    set "SIM_PAUSE=0"
) else if /i "%~1"=="--nopause" (
    set "SIM_PAUSE=0"
) else (
    echo Usage: run_sim.bat [--rtl] [--gui] [--nopause]
    exit /b 2
)
shift /1
goto args

:environment

rem Prefer the current Vivado environment, then this machine's installation.
where xvlog.bat >nul 2>&1
if not errorlevel 1 goto run
if defined XILINX_VIVADO set "PATH=%XILINX_VIVADO%\bin;%PATH%"
where xvlog.bat >nul 2>&1
if not errorlevel 1 goto run
if exist "C:\AMDDesignTools\2025.2\Vivado\bin\xvlog.bat" set "PATH=C:\AMDDesignTools\2025.2\Vivado\bin;%PATH%"

:run
echo Running bottleneck dummy simulation and Python verification...
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%SIM_SCRIPT%" %SIM_RTL% %SIM_GUI%
set "SIM_EXIT=%ERRORLEVEL%"
echo.
if "%SIM_EXIT%"=="0" (
    echo PASS: simulation and reference checks completed.
) else (
    echo FAIL: simulation or reference check failed. Exit code: %SIM_EXIT%
)
echo Logs and results: %~dp0..\..\..\AI_workspace
rem Double-click keeps the window open; /nopause is useful from a terminal.
if "%SIM_PAUSE%"=="1" pause
exit /b %SIM_EXIT%
