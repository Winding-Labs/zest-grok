@echo off
rem Delayed expansion stays off: it eats any ! in paths or args. So no !var! here, and every exec
rem sits outside ( ) blocks, where %errorlevel% is read after the command, not when the block is parsed.
setlocal DisableDelayedExpansion

set "DIR=%~dp0"
set "PLATFORM=win-x64"
set "BIN_NAME=zest-grok-win-x64.exe"

rem ── Escape hatch
if not defined ZEST_BINARY_PATH goto :read_manifest
"%ZEST_BINARY_PATH%" %*
exit /b %errorlevel%

:read_manifest
rem ── Read manifest via PowerShell. The path goes through the env, so spaces, & or ' in it need no escaping.
set "MANIFEST=%DIR%manifest.json"
if not exist "%MANIFEST%" (
  echo Zest: manifest.json missing — reinstall plugin >&2
  exit /b 1
)

set "MDATA="
for /f "usebackq delims=" %%L in (`powershell -NoProfile -ExecutionPolicy Bypass -Command "$j = Get-Content -LiteralPath $env:MANIFEST -Raw; $m = ConvertFrom-Json -InputObject $j; $a = $m.assets.'win-x64'; $s = [char]124; $m.version + $s + $m.repo + $s + $a.file + $s + $a.sha256 + $s + $a.compressed_size + $s + $a.size"`) do set "MDATA=%%L"

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

if exist "%CACHED_BIN%" goto :exec_cached

rem ── Download allowlist with fallback to previous cached version
set "VERB=%~1"
if /i "%VERB%"=="command" goto :do_download

rem Non-download verbs: try cached/sibling fallback
call :try_fallback %*
if defined FALLBACK_FOUND exit /b %errorlevel%

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
  goto :fail_fallback
)
rem Check if lock PID is alive
rem An empty pid file means the holder is still writing it.
set "LOCK_PID="
if exist "%LOCK_DIR%\pid" (
  set /p LOCK_PID=<"%LOCK_DIR%\pid"
)
if defined LOCK_PID (
  tasklist /FI "PID eq %LOCK_PID%" /NH 2>nul | findstr /i "%LOCK_PID%" >nul 2>&1
  if errorlevel 1 (
    rmdir /s /q "%LOCK_DIR%" 2>nul
    goto :lock_retry
  )
)
rem 1s sleep. Not `timeout`: it exits at once when stdin is not a console (hooks, CI).
ping -n 2 127.0.0.1 >nul
goto :lock_retry

:lock_acquired
rem Write our PID into the lock dir for stale detection. $PID is PowerShell itself, which exits
rem right away, so record its parent: the cmd.exe running this script.
powershell -NoProfile -ExecutionPolicy Bypass -Command "(Get-CimInstance Win32_Process -Filter ('ProcessId=' + $PID)).ParentProcessId" > "%LOCK_DIR%\pid"

rem Re-check cache
if exist "%CACHED_BIN%" (
  rmdir /s /q "%LOCK_DIR%" 2>nul
  goto :exec_cached
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

rem Expand-Archive on PowerShell 5.1 rejects any path that does not end in .zip.
set "TEMP_DL=%CACHE_DIR%\.download.%RANDOM%.zip"
rem The TLS 1.2 opt-in is blocked in ConstrainedLanguage mode; downloads still work there without it.
powershell -NoProfile -ExecutionPolicy Bypass -Command "try { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 } catch {}; try { Invoke-WebRequest -Uri '%URL%' -OutFile '%TEMP_DL%' -TimeoutSec 300 -UseBasicParsing } catch { Write-Error $_.Exception.Message; exit 1 }"
if errorlevel 1 (
  echo Zest: download failed. Check network or set ZEST_BINARY_PATH for manual install. >&2
  del /f /q "%TEMP_DL%" 2>nul
  rmdir /s /q "%LOCK_DIR%" 2>nul
  goto :fail_fallback
)

rem ── Decompress to temp dir, verify, then move to final path
set "EXTRACT_DIR=%CACHE_DIR%\.extract.%RANDOM%"
mkdir "%EXTRACT_DIR%"
rem System32 tar.exe, not the first tar on PATH: under Git Bash that is GNU tar, which cannot read zip.
rem Expand-Archive covers Windows without tar.exe (before 10 1803).
set "TAR_ERR=%EXTRACT_DIR%\.tar-stderr.txt"
"%SystemRoot%\System32\tar.exe" -xf "%TEMP_DL%" -C "%EXTRACT_DIR%" 2>"%TAR_ERR%"
if errorlevel 1 (
  powershell -NoProfile -ExecutionPolicy Bypass -Command "Expand-Archive -LiteralPath $env:TEMP_DL -DestinationPath $env:EXTRACT_DIR -Force"
  if errorlevel 1 (
    type "%TAR_ERR%" >&2
    echo Zest: decompression failed >&2
    del /f /q "%TEMP_DL%" 2>nul
    rmdir /s /q "%EXTRACT_DIR%" 2>nul
    rmdir /s /q "%LOCK_DIR%" 2>nul
    goto :fail_fallback
  )
)
del /f /q "%TEMP_DL%" 2>nul

set "TEMP_BIN=%EXTRACT_DIR%\%BIN_NAME%"
if not exist "%TEMP_BIN%" (
  echo Zest: decompressed binary not found >&2
  rmdir /s /q "%EXTRACT_DIR%" 2>nul
  rmdir /s /q "%LOCK_DIR%" 2>nul
  goto :fail_fallback
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
  goto :fail_fallback
)

rem ── Atomic move to final path
move /Y "%TEMP_BIN%" "%CACHED_BIN%" >nul
rmdir /s /q "%EXTRACT_DIR%" 2>nul

rem ── GC: keep pinned version + newest other (fallback for hooks after update)
set "BEST_VER=0.0.0"
for /f "delims=" %%D in ('dir /b /ad "%CACHE_BASE%" 2^>nul') do (
  if /i not "%%D"=="%VERSION%" call :keep_newer %%D
)
for /f "delims=" %%D in ('dir /b /ad "%CACHE_BASE%" 2^>nul') do (
  if /i not "%%D"=="%VERSION%" (
    if /i not "%%D"=="%BEST_VER%" rmdir /s /q "%CACHE_BASE%\%%D" 2>nul
  )
)

rem ── Release lock & exec
rmdir /s /q "%LOCK_DIR%" 2>nul
:exec_cached
set "ZEST_PINNED_VERSION="
for %%P in ("%DIR%..") do set "ZEST_PLUGIN_ROOT=%%~fP"
"%CACHED_BIN%" %*
exit /b %errorlevel%

:fail_fallback
call :try_fallback %*
if defined FALLBACK_FOUND exit /b %errorlevel%
exit /b 1

rem ── Subroutine: try cached or sibling binary as degraded fallback.
rem Sets FALLBACK_FOUND=1 and execs the binary if found. Caller checks FALLBACK_FOUND.
:try_fallback
set "FALLBACK_FOUND="
call :find_fallback
if defined FALLBACK_BIN goto :run_fallback
set "SIBLING_GLOB="
if not defined SIBLING_GLOB exit /b 0
set "BEST_VER=0.0.0"
for /f "delims=" %%D in ('dir /b /ad "%DIR%..\.." 2^>nul') do (
  if exist "%DIR%..\..\%%D\bin\%BIN_NAME%" call :keep_newer %%D
)
if "%BEST_VER%"=="0.0.0" exit /b 0
set "FALLBACK_BIN=%DIR%..\..\%BEST_VER%\bin\%BIN_NAME%"
:run_fallback
set "FALLBACK_FOUND=1"
set "ZEST_PINNED_VERSION=%VERSION%"
for %%P in ("%DIR%..") do set "ZEST_PLUGIN_ROOT=%%~fP"
"%FALLBACK_BIN%" %*
exit /b %errorlevel%

rem ── Subroutine: find newest cached binary that is not the pinned version
:find_fallback
set "FALLBACK_BIN="
set "BEST_VER=0.0.0"
for /f "delims=" %%D in ('dir /b /ad "%CACHE_BASE%" 2^>nul') do (
  if /i not "%%D"=="%VERSION%" (
    if exist "%CACHE_BASE%\%%D\%BIN_NAME%" call :keep_newer %%D
  )
)
if not "%BEST_VER%"=="0.0.0" set "FALLBACK_BIN=%CACHE_BASE%\%BEST_VER%\%BIN_NAME%"
exit /b 0

rem ── Subroutine: set BEST_VER=%1 if %1 is a newer version than BEST_VER
:keep_newer
call :ver_gt %1 %BEST_VER%
if %VER_RESULT% equ 1 set "BEST_VER=%~1"
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
if %_A1% gtr %_B1% (set "VER_RESULT=1" & exit /b 0)
if %_A1% lss %_B1% exit /b 0
if %_A2% gtr %_B2% (set "VER_RESULT=1" & exit /b 0)
if %_A2% lss %_B2% exit /b 0
if %_A3% gtr %_B3% set "VER_RESULT=1"
exit /b 0
