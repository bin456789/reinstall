@echo off
mode con cp select=437 >nul

for /f "tokens=2" %%a in ('echo list vol ^| diskpart ^| findstr /i "\<@installer_part_label@\>"') do (echo select vol %%a & echo delete partition) | diskpart
(echo select vol %SystemDrive% & echo extend) | diskpart
del "%~f0"
