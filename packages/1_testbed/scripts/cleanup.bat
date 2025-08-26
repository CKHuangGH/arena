@echo off
setlocal enabledelayedexpansion

set CLUSTER_NAME=pandora-testbed
set BIN_DIR=%USERPROFILE%\bin
set KIND=%BIN_DIR%\kind.exe
set KUBECTL=%BIN_DIR%\kubectl.exe

echo.
echo [INFO] 🔧 Starting Pandora Testbed Cleanup...

REM ───────────── Delete Kind Cluster ─────────────
echo [INFO] Checking if Kind cluster "%CLUSTER_NAME%" exists...
"%KIND%" get clusters | findstr /C:"%CLUSTER_NAME%" >nul 2>&1
if %errorlevel%==0 (
    echo [INFO] Deleting Kind cluster "%CLUSTER_NAME%"...
    "%KIND%" delete cluster --name %CLUSTER_NAME%
) else (
    echo [INFO] No cluster named "%CLUSTER_NAME%" found.
)

REM ───────────── Delete Dashboard Namespace ─────────────
echo [INFO] Deleting dashboard namespace if it exists...
"%KUBECTL%" delete namespace kubernetes-dashboard --context kind-%CLUSTER_NAME% 2>nul

REM ───────────── Remove generated config files ─────────────
echo [INFO] Cleaning up local config files...
del /q kind-cluster-config.json >nul 2>&1
del /q *.log >nul 2>&1

REM ───────────── Remove tool binaries ─────────────
echo [INFO] Removing downloaded CLI tools...
del /q "%BIN_DIR%\kind.exe" >nul 2>&1
del /q "%BIN_DIR%\kubectl.exe" >nul 2>&1
del /q "%BIN_DIR%\jq.exe" >nul 2>&1
del /q "%BIN_DIR%\helm.exe" >nul 2>&1

REM ───────────── Clean up temp folders ─────────────
rmdir /s /q "%BIN_DIR%\helm_extracted" >nul 2>&1
rmdir /s /q curl_tmp >nul 2>&1

echo.
echo [INFO] ✅ Cleanup complete.
pause
