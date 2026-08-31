@echo off
setlocal enabledelayedexpansion

set "DIR=%~dp0"
set "PLATFORM=win-x64"
set "BIN_NAME=zest-grok-win-x64.exe"

rem ── Escape hatch
if defined ZEST_BINARY_PATH (
  "%ZEST_BINARY_PATH%" %*
  exit /b !errorlevel!
)

rem ── Read manifest via PowerShell (temp script avoids inline escaping issues)
set "MANIFEST=%DIR%manifest.json"
if not exist "%MANIFEST%" (
  echo Zest: manifest.json missing — reinstall plugin >&2
  exit /b 1
)

set "MDATA_FILE=%TEMP%\zest-manifest-%RANDOM%-%RANDOM%.txt"
powershell -NoProfile -ExecutionPolicy Bypass -Command "$j = Get-Content '%MANIFEST%' -Raw; $m = ConvertFrom-Json -InputObject $j; $a = $m.assets.'win-x64'; $s = [char]124; $m.version + $s + $m.repo + $s + $a.file + $s + $a.sha256 + $s + $a.compressed_size + $s + $a.size" > "%MDATA_FILE%"
if errorlevel 1 (
  del /f /q "%MDATA_FILE%" 2>nul
  echo Zest: cannot read manifest.json >&2
  exit /b 1
)
set /p MDATA=<"%MDATA_FILE%"
del /f /q "%MDATA_FILE%" 2>nul

for /f "tokens=1-6 delims=|" %%a in ("%MDATA%") do (
  set "VERSION=%%a"
  set "REPO=%%b"
  set "ASSET_FILE=%%c"
  set "EXPECTED_SHA=%%d"
  set "COMPRESSED_SIZE=%%e"
  set "UNCOMPRESSED_SIZE=%%f"
)

if "%VERSION%"=="" (
  echo Zest: cannot parse manifest.json >&2
  exit /b 1
)

rem ── Cache check
set "CACHE_BASE=%USERPROFILE%\.zest\bin\grok"
set "CACHE_DIR=%CACHE_BASE%\%VERSION%"
set "CACHED_BIN=%CACHE_DIR%\%BIN_NAME%"

if exist "%CACHED_BIN%" (
  set "ZEST_PINNED_VERSION="
  for %%P in ("%DIR%..") do set "ZEST_PLUGIN_ROOT=%%~fP"
  "%CACHED_BIN%" %*
  exit /b !errorlevel!
)

rem ── Download allowlist with fallback to previous cached version
set "VERB=%~1"
if /i "%VERB%"=="command" goto :do_download

rem Non-download verbs: try cached/sibling fallback
call :try_fallback %*
if defined FALLBACK_FOUND exit /b !errorlevel!

if /i "%VERB%"=="hook" (
  echo {"status":"binary_not_cached","version":"%VERSION%"} >&2
  exit /b 0
)
if /i "%VERB%"=="daemon" (
  echo {"status":"binary_not_cached","version":"%VERSION%"} >&2
  exit /b 1
)
echo {"status":"binary_not_cached","version":"%VERSION%"} >&2
exit /b 0

:do_download
if not exist "%CACHE_DIR%" mkdir "%CACHE_DIR%"

rem ── Lock
set "LOCK_DIR=%CACHE_DIR%\.download-lock"
set /a "LOCK_TRIES=0"
:lock_retry
mkdir "%LOCK_DIR%" 2>nul && goto :lock_acquired
set /a "LOCK_TRIES+=1"
if %LOCK_TRIES% geq 120 (
  echo Zest: timed out waiting for download lock >&2
  call :try_fallback %*
  if defined FALLBACK_FOUND exit /b !errorlevel!
  exit /b 1
)
rem Check if lock PID is alive
if exist "%LOCK_DIR%\pid" (
  set /p LOCK_PID=<"%LOCK_DIR%\pid"
  tasklist /FI "PID eq !LOCK_PID!" /NH 2>nul | findstr /i "!LOCK_PID!" >nul 2>&1
  if errorlevel 1 (
    rmdir /s /q "%LOCK_DIR%" 2>nul
    goto :lock_retry
  )
)
timeout /t 1 /nobreak >nul
goto :lock_retry

:lock_acquired
rem Write our PID into the lock dir for stale detection
powershell -NoProfile -Command "[System.Diagnostics.Process]::GetCurrentProcess().Id" > "%LOCK_DIR%\pid"

rem Re-check cache
if exist "%CACHED_BIN%" (
  rmdir /s /q "%LOCK_DIR%" 2>nul
  set "ZEST_PINNED_VERSION="
  for %%P in ("%DIR%..") do set "ZEST_PLUGIN_ROOT=%%~fP"
  "%CACHED_BIN%" %*
  exit /b !errorlevel!
)

rem ── Download (ZEST_DOWNLOAD_BASE_URL overrides for air-gapped setups)
if defined ZEST_DOWNLOAD_BASE_URL (
  set "URL=%ZEST_DOWNLOAD_BASE_URL%/%ASSET_FILE%"
) else (
  set "URL=https://github.com/%REPO%/releases/download/v%VERSION%/%ASSET_FILE%"
)
set /a "DL_MB=%COMPRESSED_SIZE% / 1048576"
if %DL_MB% lss 1 set "DL_MB=1"
echo Zest: downloading runtime v%VERSION% (%DL_MB% MB, one time)

set "TEMP_DL=%CACHE_DIR%\.download.%RANDOM%"
powershell -NoProfile -Command "try { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12; Invoke-WebRequest -Uri '%URL%' -OutFile '%TEMP_DL%' -TimeoutSec 300 -UseBasicParsing } catch { Write-Error $_.Exception.Message; exit 1 }"
if errorlevel 1 (
  echo Zest: download failed. Check network or set ZEST_BINARY_PATH for manual install. >&2
  del /f /q "%TEMP_DL%" 2>nul
  rmdir /s /q "%LOCK_DIR%" 2>nul
  call :try_fallback %*
  if defined FALLBACK_FOUND exit /b !errorlevel!
  exit /b 1
)

rem ── Decompress to temp dir, verify, then move to final path
set "EXTRACT_DIR=%CACHE_DIR%\.extract.%RANDOM%"
mkdir "%EXTRACT_DIR%"
tar -xf "%TEMP_DL%" -C "%EXTRACT_DIR%" 2>nul
if errorlevel 1 (
  powershell -NoProfile -Command "Expand-Archive -Path '%TEMP_DL%' -DestinationPath '%EXTRACT_DIR%' -Force"
  if errorlevel 1 (
    echo Zest: decompression failed >&2
    del /f /q "%TEMP_DL%" 2>nul
    rmdir /s /q "%EXTRACT_DIR%" 2>nul
    rmdir /s /q "%LOCK_DIR%" 2>nul
    call :try_fallback %*
    if defined FALLBACK_FOUND exit /b !errorlevel!
    exit /b 1
  )
)
del /f /q "%TEMP_DL%" 2>nul

set "TEMP_BIN=%EXTRACT_DIR%\%BIN_NAME%"
if not exist "%TEMP_BIN%" (
  echo Zest: decompressed binary not found >&2
  rmdir /s /q "%EXTRACT_DIR%" 2>nul
  rmdir /s /q "%LOCK_DIR%" 2>nul
  call :try_fallback %*
  if defined FALLBACK_FOUND exit /b !errorlevel!
  exit /b 1
)

rem ── Verify SHA256 (on temp binary, before it reaches the final path)
for /f "usebackq skip=1 delims=" %%H in (`certutil -hashfile "%TEMP_BIN%" SHA256`) do (
  if not defined ACTUAL_SHA set "ACTUAL_SHA=%%H"
)
set "ACTUAL_SHA=%ACTUAL_SHA: =%"
if /i not "%ACTUAL_SHA%"=="%EXPECTED_SHA%" (
  echo Zest: integrity check failed >&2
  echo   expected: %EXPECTED_SHA% >&2
  echo   actual:   %ACTUAL_SHA% >&2
  rmdir /s /q "%EXTRACT_DIR%" 2>nul
  rmdir /s /q "%LOCK_DIR%" 2>nul
  call :try_fallback %*
  if defined FALLBACK_FOUND exit /b !errorlevel!
  exit /b 1
)

rem ── Atomic move to final path
move /Y "%TEMP_BIN%" "%CACHED_BIN%" >nul
rmdir /s /q "%EXTRACT_DIR%" 2>nul

rem ── GC: keep pinned version + newest other (fallback for hooks after update)
set "GC_NEWEST_VER=0.0.0"
set "GC_NEWEST_DIR="
for /f "delims=" %%D in ('dir /b /ad "%CACHE_BASE%" 2^>nul') do (
  if /i not "%%D"=="%VERSION%" (
    call :ver_gt %%D !GC_NEWEST_VER!
    if !VER_RESULT! equ 1 (
      set "GC_NEWEST_VER=%%D"
      set "GC_NEWEST_DIR=%%D"
    )
  )
)
for /f "delims=" %%D in ('dir /b /ad "%CACHE_BASE%" 2^>nul') do (
  if /i not "%%D"=="%VERSION%" (
    if /i not "%%D"=="!GC_NEWEST_DIR!" rmdir /s /q "%CACHE_BASE%\%%D" 2>nul
  )
)

rem ── Release lock & exec
rmdir /s /q "%LOCK_DIR%" 2>nul
set "ZEST_PINNED_VERSION="
for %%P in ("%DIR%..") do set "ZEST_PLUGIN_ROOT=%%~fP"
"%CACHED_BIN%" %*
exit /b %errorlevel%

rem ── Subroutine: try cached or sibling binary as degraded fallback.
rem Sets FALLBACK_FOUND=1 and execs the binary if found. Caller checks FALLBACK_FOUND.
:try_fallback
set "FALLBACK_FOUND="
call :find_fallback
if defined FALLBACK_BIN (
  set "FALLBACK_FOUND=1"
  set "ZEST_PINNED_VERSION=%VERSION%"
  for %%P in ("%DIR%..") do set "ZEST_PLUGIN_ROOT=%%~fP"
  "%FALLBACK_BIN%" %*
  exit /b !errorlevel!
)
set "SIBLING_GLOB="
if defined SIBLING_GLOB (
  set "BEST_SIBLING="
  set "BEST_SIBLING_VER=0.0.0"
  for /f "delims=" %%D in ('dir /b /ad "%DIR%..\.." 2^>nul') do (
    if exist "%DIR%..\..\%%D\bin\%BIN_NAME%" (
      call :ver_gt %%D !BEST_SIBLING_VER!
      if !VER_RESULT! equ 1 (
        set "BEST_SIBLING=%DIR%..\..\%%D\bin\%BIN_NAME%"
        set "BEST_SIBLING_VER=%%D"
      )
    )
  )
  if defined BEST_SIBLING (
    set "FALLBACK_FOUND=1"
    set "ZEST_PINNED_VERSION=%VERSION%"
    for %%P in ("%DIR%..") do set "ZEST_PLUGIN_ROOT=%%~fP"
    "!BEST_SIBLING!" %*
    exit /b !errorlevel!
  )
)
exit /b 0

rem ── Subroutine: find newest cached binary that is not the pinned version
:find_fallback
set "FALLBACK_BIN="
set "FALLBACK_VER=0.0.0"
for /f "delims=" %%D in ('dir /b /ad "%CACHE_BASE%" 2^>nul') do (
  if /i not "%%D"=="%VERSION%" (
    if exist "%CACHE_BASE%\%%D\%BIN_NAME%" (
      call :ver_gt %%D !FALLBACK_VER!
      if !VER_RESULT! equ 1 (
        set "FALLBACK_BIN=%CACHE_BASE%\%%D\%BIN_NAME%"
        set "FALLBACK_VER=%%D"
      )
    )
  )
)
exit /b 0

rem ── Subroutine: numeric semver comparison
rem Sets VER_RESULT=1 if %1 > %2, else VER_RESULT=0.
rem Non-version names (containing non-digit/dot chars) always lose.
:ver_gt
set "VER_RESULT=0"
set "_A1=0" & set "_A2=0" & set "_A3=0"
set "_B1=0" & set "_B2=0" & set "_B3=0"
set "_VA=%~1"
set "_VB=%~2"
rem Reject non-version names
echo %_VA%| findstr /r "^[0-9][0-9]*\.[0-9]" >nul 2>&1 || exit /b 0
echo %_VB%| findstr /r "^[0-9][0-9]*\.[0-9]" >nul 2>&1 || (set "VER_RESULT=1" & exit /b 0)
for /f "tokens=1-3 delims=." %%a in ("%_VA%") do (set /a "_A1=%%a" & set /a "_A2=%%b" & set /a "_A3=%%c" 2>nul)
for /f "tokens=1-3 delims=." %%a in ("%_VB%") do (set /a "_B1=%%a" & set /a "_B2=%%b" & set /a "_B3=%%c" 2>nul)
if not defined _A3 set /a "_A3=0"
if not defined _B3 set /a "_B3=0"
if !_A1! gtr !_B1! (set "VER_RESULT=1" & exit /b 0)
if !_A1! lss !_B1! exit /b 0
if !_A2! gtr !_B2! (set "VER_RESULT=1" & exit /b 0)
if !_A2! lss !_B2! exit /b 0
if !_A3! gtr !_B3! set "VER_RESULT=1"
exit /b 0
