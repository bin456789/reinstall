@echo off
mode con cp select=437 >nul

rem win7 find 命令在 65001 代码页下有问题，仅限 win 7
rem findstr 就正常，但安装程序又没有 findstr
rem echo a | find "a"

rem 使用高性能模式
rem https://learn.microsoft.com/windows-hardware/manufacture/desktop/capture-and-apply-windows-using-a-single-wim
rem win8 pe 没有 powercfg
call powercfg /s 8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c 2>nul

rem 安装 SCSI 驱动
for %%F in ("X:\drivers\*.inf") do (
    rem 不要查找 Class=SCSIAdapter 因为有些驱动等号两边有空格
    find /i "SCSIAdapter" "%%~F" >nul
    if not errorlevel 1 (
        drvload "%%~F"
    )
)

rem 等待加载分区
call :sleep 5000
echo rescan | diskpart

rem 判断 efi 还是 bios
rem 或者用 https://learn.microsoft.com/windows-hardware/manufacture/desktop/boot-to-uefi-mode-or-legacy-bios-mode
rem pe 下没有 mountvol
echo list vol | diskpart | find "efi" && (
    set BootType=efi
) || (
    set BootType=bios
)

rem 获取 installer 卷 id
for /f "tokens=2" %%a in ('echo list vol ^| diskpart ^| find "installer"') do (
    set "VolIndex=%%a"
)

rem 将 installer 分区设为 Y 盘
(echo select vol %VolIndex% & echo assign letter=Y) | diskpart

rem 设置虚拟内存，好像没必要，安装时会自动在 C 盘设置虚拟内存
rem wpeutil CreatePageFile /path=Y:\pagefile.sys

rem 获取主硬盘 id
rem vista pe 没有 wmic，因此用 diskpart
(echo select vol %VolIndex% & echo list disk) | diskpart | find "* " > X:\disk.txt
for /f "tokens=3" %%a in (X:\disk.txt) do (
    set "DiskIndex=%%a"
)
del X:\disk.txt

rem 重新分区/格式化
(if "%BootType%"=="efi" (
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

rem 使用 diskpart /s ，出错不会执行剩下的 diskpart 命令
diskpart /s X:\diskpart.txt
del X:\diskpart.txt

rem 盘符
rem X boot.wim (ram)
rem Y installer

rem 设置 autounattend.xml 的主硬盘 id
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

rename X:\setup.exe.disabled setup.exe

rem 运行 X:\setup.exe 的话
rem vista 会找不到安装源
rem server 23h2 会无法运行
rem Y:\setup.exe /emsport:COM1 /emsbaudrate:115200
Y:\setup.exe
exit /b

:sleep
rem 没有 timeout 命令
rem 没有加载网卡驱动，无法用 ping 来等待
echo wscript.sleep(%~1) > X:\sleep.vbs
cscript //nologo X:\sleep.vbs
del X:\sleep.vbs
exit /b
