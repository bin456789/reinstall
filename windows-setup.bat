@echo off
mode con cp select=437 >nul

rem 还原 setup.exe
rename X:\setup.exe.disabled setup.exe

rem 等待 10 秒才自动安装
cls
for /l %%i in (10,-1,1) do (
    echo Press Ctrl+C within %%i seconds to cancel the automatic installation.
    call :sleep 1000
    cls
)

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

rem 获取 ProductType
for /f "tokens=3" %%a in ('reg query "HKLM\SYSTEM\CurrentControlSet\Control\ProductOptions" /v ProductType') do (
    set "ProductType=%%a"
)

rem 获取 BuildNumber
for /f "tokens=3" %%a in ('reg query "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion" /v CurrentBuildNumber') do (
    set "BuildNumber=%%a"
)

rem 获取 installer 卷 id
for /f "tokens=2" %%a in ('echo list vol ^| diskpart ^| find "installer"') do (
    set "VolIndex=%%a"
)

rem 将 installer 分区设为 Y 盘
(echo select vol %VolIndex% & echo assign letter=Y) | diskpart

rem 旧版安装程序会自动在 C 盘设置虚拟内存
rem 新版安装程序(24h2)不会自动设置虚拟内存
rem 在 installer 分区创建虚拟内存，不用白不用
call :createPageFile

rem 查看虚拟内存
rem wmic pagefile

rem 获取主硬盘 id
rem vista pe 没有 wmic，因此用 diskpart
(echo select vol %VolIndex% & echo list disk) | diskpart | find "* Disk " > X:\disk.txt
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
    rem echo assign letter=Z
) else (
    echo select disk %DiskIndex%

    echo select part 1
    rem echo delete part override
    rem echo create part primary
    echo format fs=ntfs quick
    echo active
    rem echo assign letter=Z
)) > X:\diskpart.txt

rem 使用 diskpart /s ，出错不会执行剩下的 diskpart 命令
diskpart /s X:\diskpart.txt
del X:\diskpart.txt

rem 盘符
rem X boot.wim (ram)
rem Y installer
rem Z os

rem 旧版安装程序会自动在C盘设置虚拟内存，新版安装程序(24h2)不会
rem 如果不创建虚拟内存，1g 内存的机器安装时会报错/杀进程
if %BuildNumber% GEQ 26040 (
    rem 已经在 installer 分区创建了虚拟内存，约等于 boot.wim 的大小，因此这步不需要
    rem vista/2008 没有删除 boot.wim，200M预留空间-(文件系统占用+驱动占用)后，实测能创建1个64M虚拟内存文件
    rem call :createPageFileOnZ
)

rem 设置应答文件的主硬盘 id
set "file=X:\windows.xml"
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


rem https://github.com/pbatard/rufus/issues/1990
for %%a in (RAM TPM SecureBoot) do (
    reg add HKLM\SYSTEM\Setup\LabConfig /t REG_DWORD /v Bypass%%aCheck /d 1 /f
)

rem 设置
set ForceOldSetup=0
set EnableUnattended=1

rem 运行 ramdisk X:\setup.exe 的话
rem vista 会找不到安装源
rem server 23h2 会无法运行
if "%ForceOldSetup%"=="1" (
    set setup=Y:\sources\setup.exe
) else (
    set setup=Y:\setup.exe
)

if "%EnableUnattended%"=="1" (
    set Unattended=/unattend:X:\windows.xml
)

rem 新版安装程序默认开了 Compact OS

rem 新版安装程序不会创建 BIOS MBR 引导
rem 因此要回退到旧版，或者手动修复 MBR
rem server 2025 + bios 也是
rem 但是 server 2025 官网写支持 bios
rem TODO: 使用 ms-sys 可以不修复？
if %BuildNumber% GEQ 26040 if "%BootType%"=="bios" (
    rem set ForceOldSetup=1
    bootrec /fixmbr
)

rem 旧版安装程序不会创建 winre 分区
rem 新版安装程序会创建 winre 分区
rem winre 分区创建在 installer 分区前面
rem 禁止 winre 分区后，winre 储存在 C 盘，依然有效
if %BuildNumber% GEQ 26040 if "%ForceOldSetup%"=="0" (
    set ResizeRecoveryPartition=/ResizeRecoveryPartition Disable
)

rem 为 windows server 打开 EMS
rem 普通 windows 没有自带 EMS 组件，暂不处理
if "%ProductType%"=="ServerNT" (
    rem set EMS=/EMSPort:UseBIOSSettings /EMSBaudRate:115200
    set EMS=/EMSPort:COM1 /EMSBaudRate:115200
)

echo on
%setup% %ResizeRecoveryPartition% %EMS% %Unattended%
exit /b

:sleep
rem 没有加载网卡驱动，无法用 ping 来等待
rem 没有 timeout 命令
rem timeout /t 10 /nobreak
echo wscript.sleep(%~1) > X:\sleep.vbs
cscript //nologo X:\sleep.vbs
del X:\sleep.vbs
exit /b

:createPageFile
rem 尽量填满空间，pagefile 默认 64M
for /l %%i in (1, 1, 100) do (
    wpeutil CreatePageFile /path=Y:\pagefile%%i.sys >nul 2>nul && echo Created pagefile%%i.sys || exit /b
)
exit /b

:createPageFileOnZ
wpeutil CreatePageFile /path=Z:\pagefile.sys /size=512
exit /b
