@echo off
mode con cp select=437 >nul
setlocal enabledelayedexpansion

set "files[1]=%windir%\System32\GroupPolicy\gpt.ini"
set "files[2]=%windir%\System32\GroupPolicy\Machine\Scripts\scripts.ini"

for %%i in (1 2) do (
    set "ini=!files[%%i]!"
    if exist "!ini!.orig" (
        move /y "!ini!.orig" "!ini!"
    ) else (
        del "!ini!"
    )
)

del "%~f0"
