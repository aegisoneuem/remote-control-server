@echo off
rem Stops and removes the Aegis RC agent service. Right-click: Run as administrator.
cd /d "%~dp0"
aegis-rc-agent.exe service uninstall
pause
