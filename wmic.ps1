param(
    [string]$Namespace,
    [string]$Class,
    [string]$Filter,
    [string]$Properties
)

$propertiesToDisplay = if ($Properties) { $Properties.Split(",") } else { @("*") }

$wmiQuery = @{
    Namespace = $Namespace
    Class     = $Class
}

if ($Filter) {
    $wmiQuery.Filter = $Filter
}

Get-WmiObject @wmiQuery | ForEach-Object {
    $_.PSObject.Properties | Where-Object {
        -not $_.Name.StartsWith("__") -and
        ($propertiesToDisplay -contains $_.Name -or $propertiesToDisplay -contains "*")
    } | ForEach-Object {
        $name = $_.Name
        $value = $_.Value

        # 改成 wmic 的输出格式
        if ($value -is [Array]) {
            $formattedValue = ($value | ForEach-Object { "`"$_`"" }) -join ","
            Write-Output "$name={$formattedValue}"
        }
        else {
            Write-Output "$name=$value"
        }
    }
}
