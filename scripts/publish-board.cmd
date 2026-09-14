@echo off
REM Double-click this to refresh + rebuild + publish the hot board to Netlify.
REM Window stays open at the end so you can copy the printed link.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0publish-board.ps1" %*
echo.
pause
