@echo off
mode con cp select=437 >nul

rem set RdpPort=3333

rem https://learn.microsoft.com/windows-server/remote/remote-desktop-services/clients/change-listening-port
rem HKLM\SYSTEM\CurrentControlSet\Services\SharedAccess\Parameters\FirewallPolicy\FirewallRules

rem RemoteDesktop-Shadow-In-TCP
rem v2.33|Action=Allow|Active=TRUE|Dir=In|Protocol=6|App=%SystemRoot%\system32\RdpSa.exe|Name=@FirewallAPI.dll,-28778|Desc=@FirewallAPI.dll,-28779|EmbedCtxt=@FirewallAPI.dll,-28752|Edge=TRUE|Defer=App|

rem RemoteDesktop-UserMode-In-TCP
rem v2.33|Action=Allow|Active=TRUE|Dir=In|Protocol=6|LPort=3389|App=%SystemRoot%\system32\svchost.exe|Svc=termservice|Name=@FirewallAPI.dll,-28775|Desc=@FirewallAPI.dll,-28756|EmbedCtxt=@FirewallAPI.dll,-28752|

rem RemoteDesktop-UserMode-In-UDP
rem v2.33|Action=Allow|Active=TRUE|Dir=In|Protocol=17|LPort=3389|App=%SystemRoot%\system32\svchost.exe|Svc=termservice|Name=@FirewallAPI.dll,-28776|Desc=@FirewallAPI.dll,-28777|EmbedCtxt=@FirewallAPI.dll,-28752|

rem 设置端口
reg add "HKLM\SYSTEM\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp" /v PortNumber /t REG_DWORD /d %RdpPort% /f

rem 设置防火墙
rem 各个版本的防火墙自带的 rdp 规则略有不同
rem 全部版本都有: program=%SystemRoot%\system32\svchost.exe service=TermService
rem win7 还有:    program=System                            service=
rem 以下为并集
for %%a in (TCP, UDP) do (
    netsh advfirewall firewall add rule ^
        name="Remote Desktop - Custom Port (%%a-In)" ^
        dir=in ^
        action=allow ^
        service=any ^
        protocol=%%a ^
        localport=%RdpPort%
)

rem 家庭版没有 rdp 服务
sc query TermService
if %errorlevel% == 1060 goto :del

rem 重启服务 可以用 sc 或者 net
rem UmRdpService 依赖 TermService
rem sc stop 不能处理依赖关系，因此 sc stop TermService 前需要 sc stop UmRdpService
rem net stop 可以处理依赖关系
rem sc stop 是异步的，net stop 不是异步，但有 timeout 时间
rem TermService 运行后，UmRdpService 会自动运行

rem 如果刚好系统在启动 rdp 服务，则会失败，因此要用 goto 循环
rem The Remote Desktop Services service could not be stopped.

rem 有的机器会死循环，开机 logo 不断转圈
rem 通过 netstat netstat -ano 可以看到端口已修改成功，但rdp服务不断重启 (pid一直改变)
rem 因此限定重试次数避免死循环

set retryCount=5

:restartRDP
if %retryCount% LEQ 0 goto :del
net stop TermService /y && net start TermService || (
    set /a retryCount-=1
    timeout 10
    goto :restartRDP
)

:del
del "%~f0"
