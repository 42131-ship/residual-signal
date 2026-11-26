param(
    [ValidateSet('devices', 'export', 'install', 'launch', 'shot', 'log', 'all')]
    [string]$Action = 'all',
    [string]$ShotName = 'device',
    [int]$WaitSeconds = 6
)

# Real-device loop: export debug APK -> adb install -> launch -> screenshot / logcat.
#
# Usage (PowerShell 5.1; THIS FILE MUST STAY ASCII-ONLY -- see design/TEAM.md rule:
# Windows PowerShell 5.1 reads BOM-less UTF-8 as ANSI, CJK comments get mojibake and
# can swallow following lines into a string. Already burned once with this very file.):
#   powershell -NoProfile -File tools\deploy_android.ps1 -Action devices
#   powershell -NoProfile -File tools\deploy_android.ps1 -Action export
#   powershell -NoProfile -File tools\deploy_android.ps1 -Action all -ShotName hud
#
# Dependencies (all machine-local, none committed):
#   .tools\Godot_v4.7.2-stable_win64_console.exe   export uses 4.7.2 (templates are 4.7.2 only)
#   .tools\jdk17\jdk-17.0.21.1+2                  apksigner / JAVA_HOME
#   %LOCALAPPDATA%\Android\Sdk                     platform-tools + build-tools 36.0.0
#   %APPDATA%\Godot\export_templates\4.7.2.stable  export templates
#
# Why not pipe adb through PowerShell: the first adb call forks a resident daemon that
# inherits the stdout handle, so a PS pipeline waits for it forever. Run every external
# tool through cmd /c with file redirection instead.

$ErrorActionPreference = 'Continue'

$root = Split-Path -Parent $PSScriptRoot
$godot = Join-Path $root '.tools\Godot_v4.7.2-stable_win64_console.exe'
$jdk = Join-Path $root '.tools\jdk17\jdk-17.0.21.1+2'
$adb = Join-Path $env:LOCALAPPDATA 'Android\Sdk\platform-tools\adb.exe'
$apk = Join-Path $root 'build\android\ResidualSignal-debug.apk'
$pkg = 'com.starxin.residualsignal'
$outDir = Join-Path $root 'build\android'
# Per-process temp files: two concurrent runs must not clobber each other.
$tmpOut = Join-Path $env:TEMP ('dsh_proc_' + $PID + '_out.txt')
$tmpErr = Join-Path $env:TEMP ('dsh_proc_' + $PID + '_err.txt')
$tmpBat = Join-Path $env:TEMP ('dsh_proc_' + $PID + '.bat')
$tmpCode = Join-Path $env:TEMP ('dsh_proc_' + $PID + '_code.txt')


function Invoke-Cli {
    param([string]$Exe, [string[]]$CliArgs, [int]$TimeoutSec = 180)
    Remove-Item -LiteralPath $tmpOut, $tmpErr, $tmpCode -Force -ErrorAction SilentlyContinue
    # Write a .bat and run it: avoids Start-Process argument re-quoting (which mangles
    # quoted paths) and avoids PowerShell pipelines (which adb's daemon keeps open).
    $quoted = @($CliArgs | ForEach-Object { if ($_ -match '\s') { '"' + $_ + '"' } else { $_ } })
    $bat = @(
        '@echo off',
        ('"' + $Exe + '" ' + ($quoted -join ' ') + ' > "' + $tmpOut + '" 2> "' + $tmpErr + '"'),
        ('echo %ERRORLEVEL% > "' + $tmpCode + '"')
    ) -join "`r`n"
    [IO.File]::WriteAllText($tmpBat, $bat, (New-Object System.Text.ASCIIEncoding))
    $p = Start-Process -FilePath $env:ComSpec -ArgumentList @('/c', $tmpBat) -NoNewWindow -PassThru
    $done = $p.WaitForExit($TimeoutSec * 1000)
    if (-not $done) {
        try { $p.Kill() } catch {}
        Write-Host ('[FAIL] timeout: ' + $Exe + ' ' + ($CliArgs -join ' '))
        return @{ code = -1; text = @() }
    }
    $code = -1
    if (Test-Path -LiteralPath $tmpCode) {
        $raw = (Get-Content -LiteralPath $tmpCode -ErrorAction SilentlyContinue | Select-Object -First 1)
        if ($raw) { $code = [int]$raw.Trim() }
    }
    $text = @()
    if (Test-Path -LiteralPath $tmpOut) { $text += Get-Content -LiteralPath $tmpOut }
    if (Test-Path -LiteralPath $tmpErr) { $text += Get-Content -LiteralPath $tmpErr }
    return @{ code = $code; text = $text }
}


function Invoke-Adb {
    param([string[]]$AdbArgs, [int]$TimeoutSec = 120)
    if (-not (Test-Path -LiteralPath $adb)) { Write-Host ('[FAIL] adb missing: ' + $adb); return @{ code = -1; text = @() } }
    return Invoke-Cli -Exe $adb -CliArgs $AdbArgs -TimeoutSec $TimeoutSec
}


function Get-DeviceLines {
    $r = Invoke-Adb -AdbArgs @('devices', '-l') -TimeoutSec 30
    return @($r.text | Where-Object { $_ -match '\tdevice' })
}


function Get-Devices {
    $r = Invoke-Adb -AdbArgs @('devices', '-l') -TimeoutSec 30
    $r.text
    $dev = @($r.text | Where-Object { $_ -match '\tdevice' })
    if ($dev.Count -gt 0) { Write-Host ('[OK] ' + $dev.Count + ' device(s) online') }
    else { Write-Host '[WAIT] no device yet: plug phone, enable USB debugging, accept RSA prompt' }
}


function Invoke-Export {
    if (-not (Test-Path -LiteralPath $godot)) { Write-Host ('[FAIL] godot missing: ' + $godot); return $false }
    $env:JAVA_HOME = $jdk
    New-Item -ItemType Directory -Force $outDir | Out-Null
    $r = Invoke-Cli -Exe $godot -CliArgs @('--headless', '--path', '.', '--export-debug', 'Android', 'build/android/ResidualSignal-debug.apk') -TimeoutSec 900
    $r.text | Select-Object -Last 6
    if ((Test-Path -LiteralPath $apk) -and $r.code -eq 0) {
        $mb = [math]::Round((Get-Item -LiteralPath $apk).Length / 1MB, 1)
        Write-Host ('[OK] apk ' + $mb + ' MB -> ' + $apk)
        return $true
    }
    Write-Host ('[FAIL] export exit=' + $r.code)
    return $false
}


function Invoke-Install {
    if (-not (Test-Path -LiteralPath $apk)) { Write-Host '[FAIL] apk missing, run -Action export first'; return $false }
    if ((Get-DeviceLines).Count -eq 0) { Write-Host '[FAIL] no device online; run -Action devices'; return $false }
    $r = Invoke-Adb -AdbArgs @('install', '-r', $apk) -TimeoutSec 300
    $r.text | Select-Object -Last 3
    return ($r.code -eq 0)
}


function Invoke-Launch {
    if ((Get-DeviceLines).Count -eq 0) { Write-Host '[FAIL] no device online'; return }
    $r = Invoke-Adb -AdbArgs @('shell', 'monkey', '-p', $pkg, '-c', 'android.intent.category.LAUNCHER', '1') -TimeoutSec 60
    $r.text | Select-Object -Last 2
}


function Invoke-Shot {
    if ((Get-DeviceLines).Count -eq 0) { Write-Host '[FAIL] no device online'; return }
    $remote = '/sdcard/dsh_shot.png'
    $local = Join-Path $outDir ('shot_' + $ShotName + '.png')
    Invoke-Adb -AdbArgs @('shell', 'screencap', '-p', $remote) -TimeoutSec 60 | Out-Null
    Invoke-Adb -AdbArgs @('pull', $remote, $local) -TimeoutSec 60 | Out-Null
    Invoke-Adb -AdbArgs @('shell', 'rm', '-f', $remote) -TimeoutSec 30 | Out-Null
    if (Test-Path -LiteralPath $local) {
        $kb = [math]::Round((Get-Item -LiteralPath $local).Length / 1KB)
        Write-Host ('[OK] shot ' + $kb + ' KB -> ' + $local)
    } else { Write-Host '[FAIL] screenshot not pulled' }
}


function Invoke-Log {
    if ((Get-DeviceLines).Count -eq 0) { Write-Host '[FAIL] no device online'; return }
    $r = Invoke-Adb -AdbArgs @('logcat', '-d', '-v', 'time', '-s', 'godot:V', 'GodotEngine:V', '*:S') -TimeoutSec 60
    $r.text | Select-Object -Last 40
}


switch ($Action) {
    'devices' { Get-Devices }
    'export' { Invoke-Export | Out-Null }
    'install' { Invoke-Install | Out-Null }
    'launch' { Invoke-Launch }
    'shot' { Invoke-Shot }
    'log' { Invoke-Log }
    'all' {
        if (Invoke-Export) {
            Start-Sleep -Seconds 1
            if (Invoke-Install) {
                Start-Sleep -Seconds 2
                Invoke-Launch
                Start-Sleep -Seconds $WaitSeconds
                Invoke-Shot
            }
        }
    }
}
