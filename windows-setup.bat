@echo off

:: 安装 SCSI 驱动
for %%F in ("X:\drivers\*.inf") do (
    :: 不要查找 Class=SCSIAdapter 因为有些驱动等号两边有空格
    find /i "SCSIAdapter" "%%~F" >nul
    if not errorlevel 1 (
        drvload "%%~F"
    )
)

:: 等待加载分区
:: 没有 timeout 命令
:: 没有加载网卡驱动，无法用 ping 来等待
echo wscript.sleep(5000) > sleep.vbs
cscript //nologo sleep.vbs

:: 获取主硬盘 id
for /F "tokens=2 delims==" %%A in ('wmic logicaldisk where "VolumeName='installer'" assoc:value /resultclass:Win32_DiskPartition ^| find "DiskIndex"') do (
    set "DiskIndex=%%A"
)

:: 设置 Autounattend.xml 的主硬盘 id
set "file=X:\Autounattend.xml"
set "tempFile=X:\tmp.xml"

set "search=%%disk_id%%"
set "replace=%DiskIndex%"

(for /f "delims=" %%i in (%file%) do (
    set "line=%%i"

    setlocal EnableDelayedExpansion
    echo !line:%search%=%replace%!
    endlocal

)) > %tempFile%
move /y %tempFile% %file%

:: 执行 setup.exe
ren X:\setup.exe.disabled setup.exe
X:\setup.exe
