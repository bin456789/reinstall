@echo off
mode con cp select=437 >nul
setlocal EnableDelayedExpansion

set confhome=https://raw.githubusercontent.com/bin456789/reinstall/main
set confhome_cn=https://gitlab.com/bin456789/reinstall/-/raw/main
rem set confhome_cn=https://www.ghproxy.cc/https://raw.githubusercontent.com/bin456789/reinstall/main

set pkgs=curl,cpio,p7zip,ipcalc,dos2unix,jq,xz,gzip,zstd,openssl,bind-utils,libiconv,binutils
set cmds=curl,cpio,p7zip,ipcalc,dos2unix,jq,xz,gzip,zstd,openssl,nslookup,iconv,ar

rem 65001 代码页会乱码

rem 不要用 :: 注释
rem 否则可能会出现 系统找不到指定的驱动器

rem Windows 7 SP1 winhttp 默认不支持 tls 1.2
rem https://support.microsoft.com/en-us/topic/update-to-enable-tls-1-1-and-tls-1-2-as-default-secure-protocols-in-winhttp-in-windows-c4bd73d2-31d7-761e-0178-11268bb10392
rem 有些系统根证书没更新
rem 所以不要用https
rem 进入脚本目录
cd /d %~dp0

rem 检查是否有管理员权限
fltmc >nul 2>&1
if errorlevel 1 (
    echo Please run as administrator^^!
    exit /b
)

rem 有时 %tmp% 带会话 id，且文件夹不存在
rem https://learn.microsoft.com/troubleshoot/windows-server/shell-experience/temp-folder-with-logon-session-id-deleted
if not exist %tmp% (
    md %tmp%
)

rem 检查是否国内
if not exist geoip (
    rem 部分地区 www.cloudflare.com 被墙
    call :download http://dash.cloudflare.com/cdn-cgi/trace %~dp0geoip || goto :download_failed
)
findstr /c:"loc=CN" geoip >nul
if not errorlevel 1 (
    rem mirrors.tuna.tsinghua.edu.cn 会强制跳转 https
    set mirror=http://mirror.nju.edu.cn
    if defined confhome_cn (
        set confhome=!confhome_cn!
    ) else if defined github_proxy (
        echo !confhome! | findstr /c:"://raw.githubusercontent.com/" >nul
        if not errorlevel 1 (
            set confhome=!confhome:http://=https://!
            set confhome=!confhome:https://raw.githubusercontent.com=%github_proxy%!
        )
    )
) else (
    rem 服务器在美国 equinix 机房，不是 cdn
    set mirror=http://mirrors.kernel.org
)

call :check_cygwin_installed || (
    rem win10 arm 支持运行 x86 软件
    rem win11 arm 支持运行 x86 和 x86_64 软件
    rem wmic os get osarchitecture 显示中文
    rem wmic ComputerSystem get SystemType 显示英文

    rem SystemType
    rem windows 11 24h2 没有 wmic
    rem 有的系统精简了 powershell
    where wmic >nul 2>&1
    if not errorlevel 1 (
        for /f "tokens=*" %%a in ('wmic ComputerSystem get SystemType ^| find /i "based"') do (
            set "SystemType=%%a"
        )
    ) else (
        for /f "delims=" %%a in ('powershell -NoLogo -NoProfile -NonInteractive -Command "(Get-WmiObject win32_computersystem).SystemType"') do (
            set "SystemType=%%a"
        )
    )

    rem BuildNumber
    for /f "tokens=3" %%a in ('reg query "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion" /v CurrentBuildNumber') do (
         set /a BuildNumber=%%a
    )

    set CygwinEOL=1

    echo !SystemType! | find "ARM" > nul
    if not errorlevel 1 (
        if !BuildNumber! GEQ 22000 (
            set CygwinEOL=0
        )
    ) else (
        echo !SystemType! | find "x64" > nul
        if not errorlevel 1 (
            if !BuildNumber! GEQ 9600 (
                set CygwinEOL=0
            )
        )
    )

    rem win7/8 cygwin 已 EOL，不能用最新 cygwin 源，而要用 Cygwin Time Machine 源
    rem 但 Cygwin Time Machine 没有国内源
    rem 为了保证国内下载速度, cygwin EOL 统一使用 cygwin-archive x86 源
    if !CygwinEOL! == 1 (
        set CygwinArch=x86
        set dir=/sourceware/cygwin-archive/20221123
    ) else (
        set CygwinArch=x86_64
        set dir=/sourceware/cygwin
    )

    rem 下载 Cygwin
    if not exist setup-!CygwinArch!.exe (
        call :download http://www.cygwin.com/setup-!CygwinArch!.exe %~dp0setup-!CygwinArch!.exe || goto :download_failed
    )

    rem 安装 Cygwin
    set site=!mirror!!dir!
    start /wait setup-!CygwinArch!.exe ^
        --allow-unsupported-windows ^
        --quiet-mode ^
        --only-site ^
        --site !site! ^
        --root %SystemDrive%\cygwin ^
        --local-package-dir %~dp0cygwin-local-package-dir ^
        --packages %pkgs%

    rem 检查 Cygwin 是否成功安装
    if errorlevel 1 (
        goto :install_cygwin_failed
    ) else (
        call :check_cygwin_installed || goto :install_cygwin_failed
    )
)

rem 在c盘根目录下执行 cygpath -ua . 会得到 /cygdrive/c，因此末尾要有 /
for /f %%a in ('%SystemDrive%\cygwin\bin\cygpath -ua ./') do set thisdir=%%a

rem 下载 reinstall.sh
if not exist reinstall.sh (
    call :download_with_curl %confhome%/reinstall.sh %thisdir%reinstall.sh || goto :download_failed
    call :chmod a+x %thisdir%reinstall.sh
)

rem 为每个参数添加引号，使参数正确传递到 bash
for %%a in (%*) do (
    set "param=!param! "%%~a""
)

rem 方法1
%SystemDrive%\cygwin\bin\dos2unix -q '%thisdir%reinstall.sh'
%SystemDrive%\cygwin\bin\bash -l -c '%thisdir%reinstall.sh !param!'

rem 方法2
rem %SystemDrive%\cygwin\bin\bash reinstall.sh %*
rem 再在 reinstall.sh 里运行 source /etc/profile
exit /b





:download
rem bits 要求有 Content-Length 才能下载
rem 据说如果网络设为“按流量计费” bits 也无法下载
rem https://learn.microsoft.com/en-us/windows/win32/bits/http-requirements-for-bits-downloads
rem certutil 会被 windows Defender 报毒
rem windows server 2019 要用第二条 certutil 命令
echo Download: %~1 %~2
del /q "%~2" 2>nul
if exist "%~2" (echo Cannot delete %~2 & exit /b 1)
if not exist "%~2" certutil -urlcache -f -split "%~1" "%~2" >nul
if not exist "%~2" certutil -urlcache -split "%~1" "%~2" >nul
if not exist "%~2" exit /b 1
exit /b

:download_with_curl
rem 加 --insecure 防止以下错误
rem curl: (77) error setting certificate verify locations:
rem   CAfile: /etc/ssl/certs/ca-certificates.crt
rem   CApath: none
echo Download: %~1 %~2
%SystemDrive%\cygwin\bin\curl -L --insecure "%~1" -o "%~2"
exit /b

:chmod
%SystemDrive%\cygwin\bin\chmod "%~1" "%~2"
exit /b

:download_failed
echo Download failed.
exit /b 1

:install_cygwin_failed
echo Failed to install Cygwin.
exit /b 1

:check_cygwin_installed
set "cmds_space=%cmds:,= %"
for %%c in (%cmds_space%) do (
    if not exist "%SystemDrive%\cygwin\bin\%%c" if not exist "%SystemDrive%\cygwin\bin\%%c.exe" (
        echo %%c not found.
        exit /b 1
    )
)
exit /b 0
