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
mode con cp select=437 >nul
setlocal EnableDelayedExpansion

rem 禁用 IPv6 地址标识符的随机化，防止 IPv6 和后台面板不一致
netsh interface ipv6 set global randomizeidentifiers=disabled

rem 检查是否定义了 MAC 地址
if defined mac_addr (
    for /f %%a in ('wmic nic where "MACAddress='%mac_addr%'" get InterfaceIndex ^| findstr [0-9]') do set id=%%a
    if defined id (
        rem 配置静态 IPv4 地址和网关
        if defined ipv4_addr if defined ipv4_gateway (
        rem gwmetric 默认值为 1，自动跃点需设为 0
            netsh interface ipv4 set address !id! static !ipv4_addr! gateway=!ipv4_gateway! gwmetric=0
        )

        rem 配置静态 IPv4 DNS 服务器
        for %%i in (1, 2) do (
            if defined ipv4_dns%%i (
                netsh interface ipv4 add | findstr "dnsservers"
                if ErrorLevel 1 (
                    rem vista
                    netsh interface ipv4 add dnsserver !id! !ipv4_dns%%i! %%i
                ) else (
                    rem win7
                    netsh interface ipv4 add dnsservers !id! !ipv4_dns%%i! %%i no
                )
            )
        )

        rem 配置 IPv6 地址和网关
        if defined ipv6_addr if defined ipv6_gateway (
            netsh interface ipv6 set address !id! !ipv6_addr!
            netsh interface ipv6 add route prefix=::/0 !id! !ipv6_gateway!
        )

        rem 配置 IPv6 DNS 服务器
        for %%i in (1, 2) do (
            if defined ipv6_dns%%i (
                netsh interface ipv6 add | findstr "dnsservers"
                if ErrorLevel 1 (
                    rem vista
                    netsh interface ipv6 add dnsserver !id! !ipv6_dns%%i! %%i
                ) else (
                    rem win7
                    netsh interface ipv6 add dnsservers !id! !ipv6_dns%%i! %%i no
                )
            )
        )
    )
)

rem 删除此脚本
del "%~f0"
