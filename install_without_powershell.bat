@echo off
setlocal EnableExtensions EnableDelayedExpansion

:: طلب صلاحية Administrator مرة واحدة
net session >nul 2>&1
if %errorlevel% neq 0 (
    echo Requesting Administrator permission...
    mshta "vbscript:CreateObject(""Shell.Application"").ShellExecute(""%~f0"","""","""",""runas"",1)(window.close)"
    exit /b
)

cd /d "%~dp0"

echo ==============================
echo Building Flutter Windows app...
echo ==============================

flutter build windows

if %errorlevel% neq 0 (
    echo Build failed.
    pause
    exit /b 1
)

set "PROJECT_DIR=%cd%"
set "RELEASE_DIR=%PROJECT_DIR%\build\windows\x64\runner\Release"
set "INSTALL_DIR=C:\Program Files\KIOM\PC Agent"
set "TASK_NAME=KIOM PC Agent"

if not exist "%RELEASE_DIR%" (
    echo Release folder not found:
    echo %RELEASE_DIR%
    pause
    exit /b 1
)

set "EXE_NAME="

for %%F in ("%RELEASE_DIR%\*.exe") do (
    set "EXE_NAME=%%~nxF"
)

if "%EXE_NAME%"=="" (
    echo No EXE file found in:
    echo %RELEASE_DIR%
    pause
    exit /b 1
)

echo Found EXE: %EXE_NAME%

echo ==============================
echo Installing KIOM PC Agent...
echo ==============================

mkdir "%INSTALL_DIR%" 2>nul

xcopy "%RELEASE_DIR%\*" "%INSTALL_DIR%\" /E /I /Y

if exist "%PROJECT_DIR%\config" (
    mkdir "%INSTALL_DIR%\config" 2>nul
    xcopy "%PROJECT_DIR%\config\*" "%INSTALL_DIR%\config\" /E /I /Y
)

echo ==============================
echo Creating Windows Scheduled Task...
echo ==============================

schtasks /Create /TN "%TASK_NAME%" /TR "\"%INSTALL_DIR%\%EXE_NAME%\" --background" /SC ONLOGON /RL HIGHEST /F

if %errorlevel% neq 0 (
    echo Failed to create scheduled task.
    pause
    exit /b 1
)

echo ==============================
echo Starting KIOM PC Agent...
echo ==============================

schtasks /Run /TN "%TASK_NAME%"

echo.
echo KIOM PC Agent installed successfully.
echo It will run with Windows as Administrator.
echo.
echo Install path:
echo %INSTALL_DIR%
echo.
echo Task name:
echo %TASK_NAME%
echo.
pause
