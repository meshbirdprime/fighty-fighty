@echo off
set GODOT_46=%USERPROFILE%\Downloads\Godot_v4.6.2-stable_win64\Godot_v4.6.2-stable_win64.exe

if exist "%GODOT_46%" (
  start "" "%GODOT_46%" --path "%~dp0"
) else (
  echo Godot 4.6.2 was not found at:
  echo %GODOT_46%
  echo.
  echo Open Godot manually, choose Import, and select:
  echo %~dp0project.godot
  pause
)
