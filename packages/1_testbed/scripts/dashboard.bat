@echo off
setlocal enabledelayedexpansion

set KIND_CLUSTER_NAME=pandora-testbed
set NAMESPACE=kubernetes-dashboard
set SERVICE_NAME=kubernetes-dashboard-kong-proxy
set PORT_LOCAL=8443
set BIN_DIR=%USERPROFILE%\bin
set PATH=%BIN_DIR%;%PATH%
set HELM_EXE=%BIN_DIR%\helm.exe

REM ───────────── Banner ─────────────
echo #############################################################
echo #                                                           #
echo #     Kubernetes Dashboard Setup for Windows (Pandora)      #
echo #                                                           #
echo #############################################################

REM ─────────── Check required tools ───────────
where kubectl >nul 2>&1 || (
  echo [ERROR] kubectl not found. Install it first.
  exit /b 1
)

if not exist "%HELM_EXE%" (
  echo [INFO] Helm not found. Downloading...
  curl --ssl-no-revoke -Lo "%BIN_DIR%\helm.zip" https://get.helm.sh/helm-v3.14.2-windows-amd64.zip
  powershell -Command "Expand-Archive -Force '%BIN_DIR%\helm.zip' -DestinationPath '%BIN_DIR%\helm_extracted'"
  copy "%BIN_DIR%\helm_extracted\windows-amd64\helm.exe" "%HELM_EXE%" >nul
  del "%BIN_DIR%\helm.zip"
  rmdir /s /q "%BIN_DIR%\helm_extracted"
)

REM ─────────── Switch context ───────────
echo [INFO] Switching to context kind-%KIND_CLUSTER_NAME%
kubectl config use-context kind-%KIND_CLUSTER_NAME% >nul 2>&1
if errorlevel 1 (
  echo [ERROR] Kind cluster context not found.
  exit /b 1
)

REM ─────────── Install Dashboard ───────────
kubectl get ns %NAMESPACE% >nul 2>&1
if errorlevel 1 (
  echo [INFO] Installing Kubernetes Dashboard...
  "%HELM_EXE%" repo add kubernetes-dashboard https://kubernetes.github.io/dashboard/ --kube-context kind-%KIND_CLUSTER_NAME%
  "%HELM_EXE%" repo update --kube-context kind-%KIND_CLUSTER_NAME%
  "%HELM_EXE%" upgrade --install kubernetes-dashboard kubernetes-dashboard/kubernetes-dashboard ^
    --namespace %NAMESPACE% ^
    --create-namespace ^
    --set protocolHttp=true ^
    --set extraArgs[0]=--enable-skip-login ^
    --set extraArgs[1]=--disable-settings-save ^
    --wait --timeout 300s ^
    --kube-context kind-%KIND_CLUSTER_NAME%
)

REM ─────────── Wait for dashboard ───────────
kubectl wait --for=condition=Available deployment/kubernetes-dashboard-web -n %NAMESPACE% --timeout=300s --context kind-%KIND_CLUSTER_NAME%

REM ─────────── ServiceAccount & Token ───────────
echo [INFO] Ensuring dashboard-admin service account...
kubectl create serviceaccount dashboard-admin -n %NAMESPACE% --context kind-%KIND_CLUSTER_NAME% 2>nul
kubectl create clusterrolebinding dashboard-admin --clusterrole=cluster-admin --serviceaccount=%NAMESPACE%:dashboard-admin --context kind-%KIND_CLUSTER_NAME% 2>nul

set TOKEN=
for /f %%T in ('kubectl -n %NAMESPACE% create token dashboard-admin --context kind-%KIND_CLUSTER_NAME%') do set TOKEN=%%T

if "%TOKEN%"=="" (
  echo [ERROR] Failed to get token
  exit /b 1
)

REM ─────────── Port Forward ───────────
echo [INFO] Starting port-forward on https://localhost:%PORT_LOCAL%
for /f "tokens=5" %%P in ('netstat -ano ^| findstr :%PORT_LOCAL%') do (
  taskkill /PID %%P /F >nul 2>&1
)

start "" cmd /c "kubectl -n %NAMESPACE% port-forward svc/%SERVICE_NAME% %PORT_LOCAL%:443 --context kind-%KIND_CLUSTER_NAME%"

REM ─────────── Open in browser ───────────
set DASHBOARD_URL=https://localhost:%PORT_LOCAL%/#/login?token=%TOKEN%
start "" "chrome.exe" "%DASHBOARD_URL%" || start "" "msedge.exe" "%DASHBOARD_URL%" || start "" "%DASHBOARD_URL%"

REM ─────────── Reminder ───────────
echo.
echo [INFO] Dashboard is live.
echo [🔑 Token] %TOKEN%
echo.
echo [💡 Reminder:]
echo To reopen the dashboard:
echo   kubectl port-forward -n %NAMESPACE% svc/%SERVICE_NAME% %PORT_LOCAL%:443 --context kind-%KIND_CLUSTER_NAME%
echo   kubectl -n %NAMESPACE% create token dashboard-admin --context kind-%KIND_CLUSTER_NAME%
echo   open https://localhost:%PORT_LOCAL%/#/login?token=YOUR_TOKEN

pause