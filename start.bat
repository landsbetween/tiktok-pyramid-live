@echo off
rem Pyramid Live launcher: starts the TikTok bridge server and the Godot game window.
setlocal EnableDelayedExpansion
cd /d "%~dp0"
title Pyramid Live - keep this window open during the stream

where node >nul 2>&1 || (echo Node.js is not installed. & pause & exit /b 1)

set "CFG=%USERPROFILE%\.tiktok-pyramid-user"
if not exist "%CFG%" if exist "%USERPROFILE%\.tiktok-snake-user" copy /y "%USERPROFILE%\.tiktok-snake-user" "%CFG%" >nul
if not exist "%CFG%" (
  set /p U=Enter your TikTok username without @ and press Enter:
  call echo %%U:@=%%> "%CFG%"
)
set /p U=<"%CFG%"

rem find Godot 4 (winget install location, or GODOT env var)
if not defined GODOT (
  for /d %%d in ("%LOCALAPPDATA%\Microsoft\WinGet\Packages\GodotEngine.GodotEngine_*") do (
    for %%g in ("%%d\Godot_v4*_win64.exe") do set "GODOT=%%~fg"
  )
)
if not defined GODOT (echo Godot 4 not found. Run: winget install GodotEngine.GodotEngine & pause & exit /b 1)

rem stop anything already using the bridge port
for /f "tokens=5" %%p in ('netstat -ano ^| findstr 127.0.0.1:3001 ^| findstr LISTENING') do taskkill /F /PID %%p >nul 2>&1

git pull -q >nul 2>&1
if not exist server\node_modules (pushd server & call npm install --silent & popd)

echo.
echo  TikTok: @%U%
echo  Game window opens now. In TikTok LIVE Studio add it as Window capture ("Pyramid Live").
echo  Demo keys in the game: L like, G gift, H big gift, F follow, B earthquake, E finish, D fps
echo  To change the username delete %CFG%
echo  Keep this window open during the stream.
echo.
start "" "%GODOT%" --path "%~dp0game" -- %*
cd server
node server.js %U%
pause
