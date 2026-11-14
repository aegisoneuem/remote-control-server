@echo off
rem Installs the Aegis RC agent as a Windows service (production mode). Right-click: Run as administrator.
rem Use the same values as 2-start-agent.cmd. Put ffmpeg.exe in this folder first for H.264 video (optional).
cd /d "%~dp0"
set SERVER=wss://VM1-IP:8443
set TOKEN=PASTE-AGENT-ENROLLMENT-TOKEN
set PIN=PASTE-CERTIFICATE-SHA256
set DEVICE=%COMPUTERNAME%
aegis-rc-agent.exe service install -server %SERVER% -token %TOKEN% -trust agent-trust.pub -pin %PIN% -device %DEVICE%
aegis-rc-agent.exe service status
pause
