@echo off
setlocal enabledelayedexpansion

REM ───────────── Logging helpers ─────────────
call :log_info "🧪 Starting Chaos Mesh installation..."

set "NAMESPACE=chaos-mesh"
set "RELEASE_NAME=chaos-mesh"
set "NETWORK_CHAOS_YAML=manifests\networkchaos.yaml"

REM ───────────── Check Helm ─────────────
where helm >nul 2>&1
if errorlevel 1 (
  call :log_info "Helm not found. Installing Helm..."

  REM Detect architecture
  for /f "tokens=2 delims==" %%I in ('wmic os get osarchitecture /value ^| find "="') do set "ARCHITECTURE=%%I"
  set "ARCH_DL=amd64"
  set "HELM_VERSION=v3.14.4"
  set "HELM_OS=windows"
  set "HELM_FILE=helm-%HELM_VERSION%-%HELM_OS%-%ARCH_DL%.zip"

  powershell -Command "Invoke-WebRequest -Uri https://get.helm.sh/%HELM_FILE% -OutFile helm.zip"
  powershell -Command "Expand-Archive -Path helm.zip -DestinationPath helm_tmp -Force"

  set "USER_BIN=%USERPROFILE%\bin"
  if not exist "%USER_BIN%" mkdir "%USER_BIN%"
  move /Y "helm_tmp\windows-%ARCH_DL%\helm.exe" "%USER_BIN%\helm.exe"
  del helm.zip
  rmdir /S /Q helm_tmp
  set PATH=%USER_BIN%;%PATH%

  call :log_info "Helm installed to %USER_BIN%"
) else (
  for /f "delims=" %%h in ('helm version --short') do set "HELM_VERSION_OUTPUT=%%h"
  call :log_info "Helm found: %HELM_VERSION_OUTPUT%"
)

REM ───────────── Check for existing conflicting cluster-wide resources ─────────────
kubectl get clusterrole chaos-mesh-chaos-dashboard-cluster-level >nul 2>&1
if %errorlevel% EQU 0 (
  call :log_warn "⚠️  ClusterRole 'chaos-mesh-chaos-dashboard-cluster-level' already exists."
  call :log_warn "This may mean an old Chaos Mesh release is still installed in a different namespace."
  set /p USER_CHOICE="Do you want to delete any old releases (Y/N)? "
  if /I "!USER_CHOICE!"=="Y" (
    for /f "tokens=1,2" %%i in ('helm list -A ^| findstr chaos-mesh') do (
      call :log_info "Removing old release: %%i in namespace %%j"
      helm uninstall %%i -n %%j
      kubectl delete ns %%j
    )
  ) else (
    call :log_error "Installation aborted due to conflicting global resources."
    exit /b 1
  )
)

REM ───────────── Create namespace if not exists ─────────────
kubectl get ns %NAMESPACE% >nul 2>&1
if errorlevel 1 (
  call :log_info "Creating namespace '%NAMESPACE%'..."
  kubectl create ns %NAMESPACE%
)

REM ───────────── Add Chaos Mesh repo and update ─────────────
helm repo add chaos-mesh https://charts.chaos-mesh.org
helm repo update

REM ───────────── Detect container runtime ─────────────
set "RUNTIME=containerd"
set "SOCKET_PATH=/run/containerd/containerd.sock"
docker info >nul 2>&1
if %ERRORLEVEL% EQU 0 (
  set "RUNTIME=docker"
  set "SOCKET_PATH=/var/run/docker.sock"
  call :log_info "🧩 Docker runtime detected."
) else (
  call :log_info "🧩 Defaulting to containerd runtime."
)

REM ───────────── Install or upgrade Chaos Mesh ─────────────
helm status %RELEASE_NAME% -n %NAMESPACE% >nul 2>&1
if %ERRORLEVEL% EQU 0 (
  call :log_info "Upgrading Chaos Mesh..."
  helm upgrade %RELEASE_NAME% chaos-mesh/chaos-mesh -n %NAMESPACE% ^
    --set dashboard.create=true ^
    --set chaosDaemon.runtime=%RUNTIME% ^
    --set chaosDaemon.socketPath=%SOCKET_PATH% ^
    --set chaosDaemon.securityContext.privileged=true ^
    --reuse-values
) else (
  call :log_info "Installing Chaos Mesh..."
  helm install %RELEASE_NAME% chaos-mesh/chaos-mesh -n %NAMESPACE% ^
    --set dashboard.create=true ^
    --set chaosDaemon.runtime=%RUNTIME% ^
    --set chaosDaemon.socketPath=%SOCKET_PATH% ^
    --set chaosDaemon.securityContext.privileged=true
)

REM ───────────── Wait for controller-manager pod ready ─────────────
call :log_info "⏳ Waiting for Chaos Mesh controller-manager pod..."
kubectl wait --for=condition=Ready pod -l app.kubernetes.io/component=controller-manager -n %NAMESPACE% --timeout=180s

REM ───────────── Apply NetworkChaos manifest if exists ─────────────
if exist "%NETWORK_CHAOS_YAML%" (
  call :log_info "Applying NetworkChaos from: %NETWORK_CHAOS_YAML%"
  kubectl apply -f "%NETWORK_CHAOS_YAML%"
) else (
  call :log_warn "NetworkChaos file not found at: %NETWORK_CHAOS_YAML%"
  call :log_warn "👉 You can create a manifest like this:"
  echo.
  echo apiVersion: chaos-mesh.org/v1alpha1
  echo kind: NetworkChaos
  echo metadata:
  echo   name: example-network-delay
  echo   namespace: %NAMESPACE%
  echo spec:
  echo   action: delay
  echo   mode: one
  echo   selector:
  echo     labelSelectors:
  echo       "app": "IoT"
  echo   delay:
  echo     latency: "2s"
  echo     jitter: "100ms"
  echo   duration: "30s"
  echo   scheduler:
  echo     cron: "@every 1m"
  echo.
)

call :log_info "✅ Chaos Mesh setup complete. Access the dashboard with:"
call :log_info "   kubectl port-forward -n %NAMESPACE% svc/chaos-dashboard 2333:2333"
call :log_info "   http://localhost:2333"

pause
exit /b

REM ───────────── Functions ─────────────
:log_info
echo [INFO] %~1
goto :eof

:log_warn
echo [WARN] %~1
goto :eof

:log_error
echo [ERROR] %~1
exit /b 1
