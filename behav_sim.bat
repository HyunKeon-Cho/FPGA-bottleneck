@echo off
setlocal EnableExtensions DisableDelayedExpansion
set "ROOT=%~dp0"
set "TB_PATH=%ROOT%bottleneck\bench\tb_core"
set "PATH_LOG=%TB_PATH%\.log"
set "GUI=0"
set "PUSHED=0"
set "EXIT_CODE=0"

:options
if "%~1"=="" goto environment
if /i "%~1"=="tb_core" (
    shift
    goto options
)
if /i "%~1"=="--gui" (
    set "GUI=1"
    shift
    goto options
)
echo Usage: %~nx0 [tb_core] [--gui]
exit /b 2

:environment
if not exist "%TB_PATH%\tb_core.f" goto failed
for %%T in (xvlog.bat xelab.bat xsim.bat) do (
    where %%T >nul 2>&1
    if errorlevel 1 (
        echo [ ERROR ] %%T not found. Add Vivado bin to PATH.
        exit /b 1
    )
)
if not exist "%PATH_LOG%" mkdir "%PATH_LOG%"
pushd "%TB_PATH%"
if errorlevel 1 goto failed
set "PUSHED=1"
type nul > "%PATH_LOG%\sources.prj"
for /f "usebackq eol=# delims=" %%F in ("tb_core.f") do (
    if not exist "%%F" (
        echo [ ERROR ] Source not found: %%F
        set "EXIT_CODE=1"
    )
    >> "%PATH_LOG%\sources.prj" echo sv work "%%~fF"
)
popd
set "PUSHED=0"
if "%EXIT_CODE%"=="1" goto failed
pushd "%PATH_LOG%"
if errorlevel 1 goto failed
set "PUSHED=1"
rem Invalidate an earlier pass before compiling the current sources.
type nul > simulate.log

echo [1/3] Compiling HDL...
call xvlog.bat -prj sources.prj -i "%TB_PATH%" -log compile.log
if errorlevel 1 goto failed
echo [2/3] Elaborating tb_core...
call xelab.bat tb_core -s behav_tb -debug typical -log elaborate.log
if errorlevel 1 goto failed
echo [3/3] Running case1...
if "%GUI%"=="1" (
    call xsim.bat behav_tb -gui -onfinish stop -runall -log simulate.log
) else (
    call xsim.bat behav_tb -runall -log simulate.log
)
if errorlevel 1 goto failed
rem XSim may return zero after a HDL fatal, so check the TB result as well.
findstr /l /c:"Fatal:" simulate.log >nul
if not errorlevel 1 goto failed
findstr /l /c:"[ PASS ] ALL TESTS PASSED" simulate.log >nul
if errorlevel 1 goto failed
goto finish

:failed
echo [ ERROR ] Simulation did not pass. See "%PATH_LOG%".
set "EXIT_CODE=1"
:finish
if "%PUSHED%"=="1" popd
exit /b %EXIT_CODE%
