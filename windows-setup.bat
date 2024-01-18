@echo off

:: 使用高性能模式
:: https://learn.microsoft.com/windows-hardware/manufacture/desktop/capture-and-apply-windows-using-a-single-wim
:: win8 pe 没有 powercfg
call powercfg /s 8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c 2>nul

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
:: 注意 vista pe 没有 wmic
for /F "tokens=2 delims==" %%A in ('wmic logicaldisk where "VolumeName='installer'" assoc:value /resultclass:Win32_DiskPartition ^| find "DiskIndex"') do (
    set "DiskIndex=%%A"
)

:: 判断 efi 还是 bios
echo list vol | diskpart | find "efi" && (
    set boot_type=efi
) || (
    set boot_type=bios
)

:: 重新分区/格式化
(if "%boot_type%"=="efi" (
    echo select disk %DiskIndex%

    echo select part 1
    echo delete part override
    echo select part 2
    echo delete part override
    echo select part 3
    echo delete part override

    echo create part efi size=100
    echo format fs=fat32 quick

    echo create part msr size=16

    echo create part primary
    echo format fs=ntfs quick
) else (
    echo select disk %DiskIndex%

    echo select part 1
    echo format fs=ntfs quick
)) > X:\diskpart.txt


:: 使用 diskpart /s ，出错不会执行剩下的 diskpart 命令
diskpart /s X:\diskpart.txt

:: 设置 autounattend.xml 的主硬盘 id
set "file=X:\autounattend.xml"
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
rename X:\setup.exe.disabled setup.exe
X:\setup.exe /emsport:COM1 /emsbaudrate:115200
