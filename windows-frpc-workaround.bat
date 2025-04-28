@echo off
mode con cp select=437 >nul

rem 如果找到 LOCAL SERVICE 运行的 frpc，则结束 SYSTEM 运行的 frpc
rem 如果没找到 frpc，则运行 frpc（本脚本是用 SYSTEM 运行，好像无法 runas "NT AUTHORITY\LOCAL SERVICE"）

rem tasklist 返回值始终为 0，因此需要用 findstr

:loop
tasklist /FI "IMAGENAME eq frpc.exe" /FI "USERNAME eq NT AUTHORITY\LOCAL SERVICE" | findstr /I "frpc.exe" && goto :kill_system_frpc
tasklist /FI "IMAGENAME eq frpc.exe" | findstr /I "frpc.exe" || start %SystemDrive%\frpc\frpc.exe -c %SystemDrive%\frpc\frpc.toml
timeout 5
goto :loop

:kill_system_frpc
taskkill /F /T /FI "IMAGENAME eq frpc.exe" /FI "USERNAME eq NT AUTHORITY\SYSTEM"

del "%~f0"
