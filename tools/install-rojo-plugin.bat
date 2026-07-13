@echo off
setlocal
set "PLUGINS=%LOCALAPPDATA%\Roblox\Plugins"
set "SCRIPT_DIR=%~dp0"
set "SOURCE=%SCRIPT_DIR%Rojo.rbxm"

if not exist "%SOURCE%" (
    echo ERROR: Rojo.rbxm not found at %SOURCE%
    exit /b 1
)

if not exist "%PLUGINS%" (
    mkdir "%PLUGINS%"
)

copy /Y "%SOURCE%" "%PLUGINS%\Rojo.rbxm"
echo Installed Rojo 7.7.0 plugin to:
echo   %PLUGINS%\Rojo.rbxm
echo.
echo Next steps:
echo   1. Restart Roblox Studio
echo   2. In Manage Plugins, disable or remove any older Marketplace Rojo plugin
echo   3. Connect to rojo serve at localhost:34872
