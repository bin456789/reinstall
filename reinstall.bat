@echo off
set confhome=https://raw.githubusercontent.com/bin456789/reinstall/main
setlocal EnableDelayedExpansion

:: Windows 7 SP1 winhttp 默认不支持 tls 1.2
:: https://support.microsoft.com/en-us/topic/update-to-enable-tls-1-1-and-tls-1-2-as-default-secure-protocols-in-winhttp-in-windows-c4bd73d2-31d7-761e-0178-11268bb10392
:: 有些系统根证书没更新
:: 所以不要用https
:: 进入脚本目录
cd /d %~dp0

:: 检查是否有管理员权限
openfiles 1>nul 2>&1
if not !errorlevel! == 0 (
    echo Please run as administrator^^!
    exit 1
)

:: 检查是否国内
if not exist %tmp%\geoip (
    call :download https://www.cloudflare.com/cdn-cgi/trace %tmp%\geoip
)
findstr /c:"loc=CN" %tmp%\geoip >nul
if !errorlevel! == 0 (
    set mirror=http://mirror.nju.edu.cn

    echo !confhome! | findstr /c:"://raw.githubusercontent.com/" >nul
    if !errorlevel! == 0 (
        set confhome=https://ghps.cc/!confhome!
    )
) else (
    set mirror=http://mirrors.kernel.org
)


:: pkgs 改动了才重新运行 Cygwin 安装程序
set pkgs="curl,cpio,p7zip,bind-utils,ipcalc"
set tags=%tmp%\cygwin-installed-!pkgs!
if not exist !tags! (
    :: 检查32/64位
    wmic os get osarchitecture | findstr /c:"64" >nul
    if !errorlevel! == 0 (
        set arch=x86_64
        set dir=/sourceware/cygwin
    ) else (
        set arch=x86
        set dir=/sourceware/cygwin-archive/20221123
    )

    :: 下载 Cygwin
    call :download http://www.cygwin.com/setup-!arch!.exe %tmp%\setup-cygwin.exe

    :: 安装 Cygwin
    set site=!mirror!!dir!
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
    call :download %confhome%/reinstall.sh %~dp0reinstall.sh
)

:: 运行 reinstall.sh
:: 方法1:
:: 在c盘根目录下执行 cygpath -ua . 会得到 /cygdrive/c，因此末尾要有 /
for /f %%a in ('%SystemDrive%\cygwin\bin\cygpath -ua ./') do set thisdir=%%a
%SystemDrive%\cygwin\bin\bash -l -c "%thisdir%reinstall.sh %*"

:: 方法2:
:: set PATH=/usr/local/bin:/usr/bin
:: %SystemDrive%\cygwin\bin\bash reinstall.sh %*
exit /b !errorlevel!





:download
:: bits 要求有 Content-Length 才能下载
:: https://learn.microsoft.com/en-us/windows/win32/bits/http-requirements-for-bits-downloads
:: certutil 会被 windows Defender 报毒
echo Download: %~1 %~2
certutil -urlcache -f -split %~1 %~2
exit /b !errorlevel!
