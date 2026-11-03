param([switch]$UseRtl, [switch]$Gui)
$ErrorActionPreference = 'Stop'
$taskRoot = Split-Path $PSScriptRoot -Parent
$runDir = Join-Path $PSScriptRoot 'run'
$logDir = Join-Path $runDir 'logs'
New-Item -ItemType Directory -Force -Path $logDir | Out-Null
$rtlName = if ($UseRtl) { 'rtl' } else { 'rtl_dummy' }
$rtl = Join-Path $taskRoot "bottleneck/$rtlName"
$summaryLog = Join-Path $logDir 'run.log'
Set-Content $summaryLog "Bottleneck simulation: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')`r`nRTL: $rtl" -Encoding UTF8

function Write-Status([string]$Message) {
    Add-Content $summaryLog $Message -Encoding UTF8
    Write-Host $Message
}

function Invoke-Logged([string]$Name, [string]$Program, [string[]]$Arguments) {
    $stageLog = Join-Path $logDir "$Name.log"
    Write-Status "Running $Name (log: $stageLog)"
    # Capture native stdout and stderr, including failed compiler diagnostics.
    $stdout = Join-Path $logDir "$Name.stdout.log"
    $stderr = Join-Path $logDir "$Name.stderr.log"
    $quoted = @($Arguments | ForEach-Object { '"' + $_ + '"' })
    $command = '& "' + $Program + '" ' + ($quoted -join ' ')
    $command += '; exit $LASTEXITCODE'
    $encoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($command))
    $process = Start-Process powershell.exe -ArgumentList @('-NoLogo','-NoProfile','-EncodedCommand',$encoded) `
        -WindowStyle Hidden -Wait -PassThru -RedirectStandardOutput $stdout -RedirectStandardError $stderr
    @("=== stdout ===", (Get-Content $stdout -Raw), "=== stderr ===", (Get-Content $stderr -Raw)) |
        Set-Content $stageLog -Encoding UTF8
    if ($process.ExitCode -ne 0) { throw "$Name failed (exit $($process.ExitCode)). See $stageLog" }
}

Push-Location $runDir
try {
    $sources = @(Get-ChildItem -LiteralPath $rtl -File | Where-Object { $_.Extension -in '.v','.sv' } | Sort-Object Name | ForEach-Object { $_.FullName })
    if ($sources.Count -eq 0) { throw "No .v/.sv sources in $rtl. Add RTL modules or run without --rtl for dummy modules." }
    Invoke-Logged 'reference' 'python' @((Join-Path $PSScriptRoot 'generate_reference.py'))
    $tb = Join-Path $taskRoot 'bottleneck/bench/tb_core/tb_core.v'
    Invoke-Logged 'compile' 'xvlog.bat' (@('-sv','-i',$PSScriptRoot,'-i',$rtl) + $sources + @($tb))
    Invoke-Logged 'elaborate' 'xelab.bat' @('tb_core','-s','dummy_tb','-debug','typical')
    Invoke-Logged 'simulate' 'xsim.bat' @('dummy_tb','-runall','-log',(Join-Path $logDir 'xsim.log'))
    if (-not (Select-String -Path (Join-Path $logDir 'xsim.log') -Pattern 'ALL TESTS PASSED' -Quiet)) { throw 'TB did not pass. See logs/xsim.log' }
    Invoke-Logged 'verify' 'python' @((Join-Path $PSScriptRoot 'check_results.py'))
    Write-Status 'PASS: simulation and Python verification completed.'
    Write-Status "SNR and comparisons: $(Join-Path $logDir 'verify.log')"
    if ($Gui) {
        # Give each GUI its own snapshot so it cannot lock the next compilation.
        # Keep the same directory depth as run/ for the TB's relative data paths.
        $guiDir = Join-Path $PSScriptRoot ('gui_run_' + (Get-Date -Format 'yyyyMMdd_HHmmss_fff'))
        New-Item -ItemType Directory -Path $guiDir | Out-Null
        Copy-Item -LiteralPath (Join-Path $runDir 'xsim.dir') -Destination $guiDir -Recurse
        $guiScript = (Join-Path $PSScriptRoot 'gui.tcl').Replace('\','/')
        $guiLog = Join-Path $guiDir 'xsim_gui.log'
        $guiCommand = '& xsim.bat dummy_tb -gui -onfinish stop -tclbatch "' + $guiScript + '" -log "' + $guiLog + '"; exit $LASTEXITCODE'
        $guiEncoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($guiCommand))
        $guiProcess = Start-Process powershell.exe -ArgumentList @('-NoLogo','-NoProfile','-EncodedCommand',$guiEncoded) `
            -WorkingDirectory $guiDir -WindowStyle Hidden -PassThru -RedirectStandardOutput (Join-Path $guiDir 'gui.stdout.log') -RedirectStandardError (Join-Path $guiDir 'gui.stderr.log')
        Write-Status "GUI launched (launcher PID $($guiProcess.Id)); log: $guiLog"
    }
} catch {
    Write-Status "FAIL: $($_.Exception.Message)"
    exit 1
} finally { Pop-Location }
