rem set mac_addr=11:22:33:aa:bb:cc

rem set ipv4_addr=192.168.1.2/24
rem set ipv4_gateway=192.168.1.1
rem set ipv4_dns1=192.168.1.1
rem set ipv4_dns2=192.168.1.2

rem set ipv6_addr=2222::2/64
rem set ipv6_gateway=2222::1
rem set ipv6_dns1=::1
rem set ipv6_dns2=::2

@echo off
setlocal EnableDelayedExpansion

:: 关闭随机地址，防止ipv6地址和后台面板不一致
netsh interface ipv6 set global randomizeidentifiers=disabled

if not defined mac_addr exit /b
for /f %%a in ('wmic nic where "MACAddress='%mac_addr%'" get InterfaceIndex ^| findstr [0-9]') do set id=%%a
if not defined id exit /b

if defined ipv4_addr if defined ipv4_gateway (
    :: gwmetric 默认值为 1，自动跃点需设为 0
    netsh interface ipv4 set address %id% static %ipv4_addr% gateway=%ipv4_gateway% gwmetric=0

    for %%i in (1, 2) do (
        if defined ipv4_dns%%i (
            netsh interface ipv4 add dnsservers %id% !ipv4_dns%%i! %%i no
        )
    )
)

if defined ipv6_addr if defined ipv6_gateway (
    netsh interface ipv6 set address %id% %ipv6_addr%
    netsh interface ipv6 add route prefix=::/0 %id% !ipv6_gateway!

    for %%i in (1, 2) do (
        if defined ipv6_dns%%i (
            netsh interface ipv6 add dnsservers %id% !ipv6_dns%%i! %%i no
        )
    )
)

del "%~f0"
