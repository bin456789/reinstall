@echo off
set confhome=https://raw.githubusercontent.com/bin456789/reinstall/main
setlocal EnableDelayedExpansion

:: 进入脚本目录
cd /d %~dp0

:: 检查是否有管理员权限
openfiles 1>nul 2>&1
if not !errorlevel! == 0 (
    echo "Please run as administrator!"
    exit 1
)

:: pkgs 改动了才重新运行 Cygwin 安装程序
set pkgs="curl,cpio,p7zip"
set tags=%tmp%\cygwin-installed-!pkgs!
if not exist !tags! (
    :: 检查是否国内
    :: 在括号里面，:: 下一行不能是空行!!!!!
    call :download https://geoip.fedoraproject.org/city %tmp%\geoip "Check Location"
    findstr CHN %tmp%\geoip >nul
    if !errorlevel! == 0 (
        set host=https://mirrors.tuna.tsinghua.edu.cn
    ) else (
        set host=https://mirrors.kernel.org
    )

    :: 检查32/64位
    wmic os get osarchitecture | findstr 64 >nul
    if !errorlevel! == 0 (
        set arch=x86_64
        set dir=/sourceware/cygwin
    ) else (
        set arch=x86
        set dir=/sourceware/cygwin-archive/20221123
    )

    :: 下载 Cygwin
    call :download https://www.cygwin.com/setup-!arch!.exe %tmp%\setup-cygwin.exe "Download Cygwin"

    :: 安装 Cygwin
    set site=!host!!dir!
    %tmp%\setup-cygwin.exe --allow-unsupported-windows^
                            --quiet-mode^
                            --only-site^
                            --site !site!^
                            --root %SystemDrive%\cygwin^
                            --local-package-dir %tmp%\cygwin-local-package-dir^
                            --packages !pkgs!^
    && echo >!tags!
)

:: 下载 reinstall.sh
if not exist reinstall.sh (
    call :download %confhome%/reinstall.sh %~dp0reinstall.sh "Download reinstall.sh"
)

:: 运行 reinstall.sh
:: 方法1:
for /f %%a in ('%SystemDrive%\cygwin\bin\cygpath -ua .') do set thisdir=%%a
%SystemDrive%\cygwin\bin\bash -l -c "%thisdir%reinstall.sh %*"

:: 方法2:
:: set PATH=/usr/local/bin:/usr/bin
:: %SystemDrive%\cygwin\bin\bash reinstall.sh %*
exit /b !errorlevel!





:download
:: coreutil 会被 windows Defender 报毒
:: certutil -urlcache -f -split %~1 %~2
bitsadmin /transfer "%~3" /priority foreground %~1 %~2
exit /b !errorlevel!
