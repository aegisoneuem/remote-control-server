@echo off
rem Aegis RC agent. Run on the endpoint as the signed-in user (Run as administrator to lock local input in privacy mode).
rem Fill in the four values printed by the server on its first run.
cd /d "%~dp0"
set SERVER=wss://192.168.1.10:8443
set TOKEN=PASTE-AGENT-ENROLLMENT-TOKEN
set PIN=PASTE-CERTIFICATE-SHA256
set DEVICE=PC-DEL-102
aegis-rc-agent.exe -server %SERVER% -token %TOKEN% -trust agent-trust.pub -pin %PIN% -device %DEVICE%
pause
