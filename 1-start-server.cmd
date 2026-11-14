@echo off
rem Aegis RC server (signaling, TLS 1.3 only). Run on the PC that operators connect to.
rem Replace 192.168.1.10 with this PC's LAN IP so it is in the certificate.
cd /d "%~dp0"
aegis-rc-server.exe -addr :8443 -data aegis-rc-data -hosts 192.168.1.10
pause
