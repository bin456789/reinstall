@echo off
mode con cp select=437 >nul
setlocal EnableDelayedExpansion

set confhome=https://raw.githubusercontent.com/bin456789/reinstall/main
set confhome_cn=https://cnb.cool/bin456789/reinstall/-/git/raw/main
rem set confhome_cn=https://www.ghproxy.cc/https://raw.githubusercontent.com/bin456789/reinstall/main

set pkgs=curl,cpio,p7zip,dos2unix,jq,xz,gzip,zstd,openssl,bind-utils,libiconv,binutils
set cmds=curl,cpio,p7zip,dos2unix,jq,xz,gzip,zstd,openssl,nslookup,iconv,ar

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
rem if not exist %tmp% (
rem     md %tmp%
rem )

rem 下载 geoip
if not exist geoip (
    rem www.cloudflare.com/dash.cloudflare.com 国内访问的是美国服务器，而且部分地区被墙
    call :download http://www.qualcomm.cn/cdn-cgi/trace %~dp0geoip || goto :download_failed
)

rem 判断是否有 loc=
findstr /c:"loc=" geoip >nul
if errorlevel 1 (
    echo Invalid geoip file
    del geoip
    exit /b 1
)

rem 检查是否国内
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

    rem windows 11 24h2 没有 wmic
    rem wmic os get osarchitecture 显示中文，即使设置了 mode con cp select=437
    rem wmic ComputerSystem get SystemType 显示英文
    rem for /f "tokens=*" %%a in ('wmic ComputerSystem get SystemType ^| find /i "based"') do (
    rem     set "SystemType=%%a"
    rem )

    rem 有的系统精简了 powershell
    rem for /f "delims=" %%a in ('powershell -NoLogo -NoProfile -NonInteractive -Command "(Get-WmiObject win32_computersystem).SystemType"') do (
    rem     set "SystemType=%%a"
    rem )

    rem SystemArch
    for /f "tokens=3" %%a in ('reg query "HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\Environment" /v PROCESSOR_ARCHITECTURE') do (
        set SystemArch=%%a
    )

    rem 也可以用 PROCESSOR_ARCHITEW6432 和 PROCESSOR_ARCHITECTURE 判断
    rem ARM64 win11  PROCESSOR_ARCHITEW6432   PROCESSOR_ARCHITECTURE
    rem 原生cmd          未定义                      ARM64
    rem 32位cmd          ARM64                       x86

    rem if defined PROCESSOR_ARCHITEW6432 (
    rem     set "SystemArch=%PROCESSOR_ARCHITEW6432%"
    rem ) else (
    rem     set "SystemArch=%PROCESSOR_ARCHITECTURE%"
    rem )

    rem BuildNumber
    for /f "tokens=3" %%a in ('reg query "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion" /v CurrentBuildNumber') do (
        set /a BuildNumber=%%a
    )

    set CygwinEOL=1

    echo !SystemArch! | find "ARM" > nul
    if not errorlevel 1 (
        if !BuildNumber! GEQ 22000 (
            set CygwinEOL=0
        )
    ) else (
        echo !SystemArch! | find "AMD64" > nul
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

    rem 少于 1M 视为无效
    rem 有的 IP 被官网拉黑，无法下载 exe，下载得到 html
    for %%A in (setup-!CygwinArch!.exe) do if %%~zA LSS 1048576 (
        echo Invalid Cgywin installer
        del setup-!CygwinArch!.exe
        exit /b 1
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
    if errorlevel 1 goto :install_cygwin_failed
    call :check_cygwin_installed || goto :install_cygwin_failed
)

rem 在c盘根目录下执行 cygpath -ua . 会得到 /cygdrive/c，因此末尾要有 /
for /f %%a in ('%SystemDrive%\cygwin\bin\cygpath -ua ./') do set thisdir=%%a

rem 下载 reinstall.sh
if not exist reinstall.sh (
    call :download_with_curl %confhome%/reinstall.sh %thisdir%reinstall.sh || goto :download_failed
    call :chmod a+x %thisdir%reinstall.sh
)

rem %* 无法处理 --iso https://x.com/?yyy=123
rem 为每个参数添加引号，使参数正确传递到 bash
rem for %%a in (%*) do (
rem     set "param=!param! "%%~a""
rem )

rem 转成 unix 格式，避免用户用 windows 记事本编辑后换行符不对
%SystemDrive%\cygwin\bin\dos2unix -q '%thisdir%reinstall.sh'

rem 用 bash 运行
rem %SystemDrive%\cygwin\bin\bash -l %thisdir%reinstall.sh %* 运行后会清屏
rem 因此不能用 -l
rem 这就需要在 reinstall.sh 里运行 source /etc/profile
rem 或者添加 export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:$PATH
%SystemDrive%\cygwin\bin\bash %thisdir%reinstall.sh %*
exit /b

rem bits 要求有 Content-Length 才能下载
rem cloudflare 的 cdn-cgi/trace 没有 Content-Length
rem 据说如果网络设为“按流量计费” bits 也无法下载
rem https://learn.microsoft.com/en-us/windows/win32/bits/http-requirements-for-bits-downloads
rem bitsadmin /transfer "%~3" /priority foreground %~1 %~2

:download
rem certutil 会被 windows Defender 报毒
rem windows server 2019 要用第二条 certutil 命令
echo Download: %~1 %~2
del /q "%~2" 2>nul
if exist "%~2" (echo Cannot delete %~2 & exit /b 1)

certutil -urlcache -f -split "%~1" "%~2" >nul
if not errorlevel 1 if exist "%~2" exit /b 0

certutil -urlcache -split "%~1" "%~2" >nul
if not errorlevel 1 if exist "%~2" exit /b 0

rem 下载失败时删除文件，防止下载了一部分导致下次运行时跳过了下载
del /q "%~2" 2>nul
exit /b 1

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
        exit /b 1
    )
)
exit /b 0
