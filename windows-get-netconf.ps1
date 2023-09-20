# 物理网卡
foreach ($NetAdapter in Get-NetAdapter -Physical) {
    $Name = $NetAdapter.Name
    $MACAddress = $NetAdapter.MACAddress -replace '-', ':' 

    # IP条目
    $IPEntries = (Get-NetIPAddress -InterfaceAlias $Name | 
        Where-Object {
            $_.PrefixOrigin -match "RouterAdvertisement|DHCP|Manual" -and 
            $_.AddressState -eq "Preferred" 
        })

    if (!$IPEntries) {
        continue;
    }
   
    # IPv4
    foreach ($IPEntry in $IPEntries) {
        if ($IPEntry.AddressFamily -eq "IPv4") {
            $IPAddress4 = $IPEntry.IPAddress
            $PrefixLength4 = $IPEntry.PrefixLength
            break
        }
    }

    # IPv6
    foreach ($IPEntry in $IPEntries) {
        if ($IPEntry.AddressFamily -eq "IPv6") {
            $IPAddress6 = $IPEntry.IPAddress
            $PrefixLength6 = $IPEntry.PrefixLength
            break
        }
    }
 
    # IPv4 网关
    foreach ($NetRoute in Get-NetRoute | Where-Object {
            $_.InterfaceAlias -eq $Name -and
            $_.DestinationPrefix -eq "0.0.0.0/0"
        }) {
        $DefaultIPGateway4 = $NetRoute.NextHop
        break
    }

    # IPv6 网关
    foreach ($NetRoute in Get-NetRoute | Where-Object {
            $_.InterfaceAlias -eq $Name -and
            $_.DestinationPrefix -eq "::/0"
        }) {
        $DefaultIPGateway6 = $NetRoute.NextHop
        break
    }
   
    $OutputObj = New-Object -Type PSObject -Property @{
        MACAddress        = "$MACAddress".ToLower() # 和linux保持一致
        IPAddress4        = $(If ($IPAddress4) { "$IPAddress4/$PrefixLength4" })
        IPAddress6        = $(If ($IPAddress6) { "$IPAddress6/$PrefixLength6" })
        DefaultIPGateway4 = $DefaultIPGateway4
        DefaultIPGateway6 = $DefaultIPGateway6
    }

    # 按指定顺序输出
    $OutputObj | Select-Object MACAddress, IPAddress4, IPAddress6, DefaultIPGateway4, DefaultIPGateway6 
    break
} 
