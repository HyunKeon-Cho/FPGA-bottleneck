@echo off
setlocal EnableExtensions DisableDelayedExpansion

rem ----------------------------------------------------------------
rem init
rem ----------------------------------------------------------------
for %%I in ("%~dp0.") do set "ROOT=%%~fI"

set "PATH_BASE_TB=%ROOT%\bottleneck\bench"
set "CONFIG_GUI=0"
set "EXIT_CODE=0"
set "PATH_PUSHED=0"

if "%~1"=="" ( goto error_args )

set "TB_NAME=%~1"
set "TB_PATH=%PATH_BASE_TB%\%TB_NAME%"
set "PATH_LOG=%TB_PATH%\.log"
set "TB_FILES=%TB_PATH%\%TB_NAME%.f"
shift /1

:options
if "%~1"=="" goto environment
if /i "%~1"=="--gui" (
    set "CONFIG_GUI=1"
) else (
    echo Usage: %~nx0 TB_NAME [--gui]
    exit /b 2
)
shift /1
goto options

rem ----------------------------------------------------------------
rem check environment
rem ----------------------------------------------------------------
:environment
if not exist "%PATH_LOG%" mkdir "%PATH_LOG%"

pushd "%TB_PATH%"

set "PATH_PUSHED=1"
type nul > "%PATH_LOG%\sources.prj"
for /f "usebackq eol=# delims=" %%F in ("%TB_FILES%") do (
    >> "%PATH_LOG%\sources.prj" echo sv work "%%~fF"
)
popd
set "PATH_PUSHED=0"

pushd "%PATH_LOG%"
if errorlevel 1 ( goto error_compile )
set "PATH_PUSHED=1"

echo ----------------------------------------------------------------
echo [1/3] Compiling HDL...
echo ----------------------------------------------------------------

call xvlog.bat -prj sources.prj -i "%TB_PATH%" -log "%PATH_LOG%\compile.log"
if errorlevel 1 ( goto error_compile )

echo ----------------------------------------------------------------
echo [2/3] Elaborating %TB_NAME%...
echo ----------------------------------------------------------------

call xelab.bat "%TB_NAME%" -s behav_tb -debug typical -log "%PATH_LOG%\elaborate.log"
if errorlevel 1 ( goto error_elaborate )

echo ----------------------------------------------------------------
echo [3/3] Running behavioral simulation...
echo ----------------------------------------------------------------
call xsim.bat behav_tb -runall -log "%PATH_LOG%\simulate.log"
if errorlevel 1 ( goto error_simulate )

if "%CONFIG_GUI%"=="1" (
    call xsim.bat behav_tb -gui -onfinish stop -runall -log "%PATH_LOG%\xsim_gui.log"
    if errorlevel 1 ( goto error_simulate )
)

goto finish

rem ----------------------------------------------------------------
rem error
rem ----------------------------------------------------------------

:error_args
echo [ ERROR ] Missing required arguments
exit /b 1

:error_compile
echo [ ERROR ] Compilation failed. See "%PATH_LOG%\compile.log".
set "EXIT_CODE=1"
goto finish

:error_elaborate
echo [ ERROR ] Elaboration failed. See "%PATH_LOG%\elaborate.log".
set "EXIT_CODE=1"
goto finish

:error_simulate
echo [ ERROR ] Simulation failed. See "%PATH_LOG%\simulate.log".
set "EXIT_CODE=1"
goto finish

:finish
if "%PATH_PUSHED%"=="1" popd
exit /b %EXIT_CODE%

