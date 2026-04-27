param(
    [string]$Namespace = "root\cimv2",
    [Parameter(Mandatory = $true)] [string]$Class,
    [string]$Filter,
    [string]$Properties
)

# 预处理属性列表：如果有输入则处理成数组，否则保持为空数组
[string[]]$propertyList = if ($Properties) {
    $Properties.Split(",") | ForEach-Object { $_.Trim() }
}
else {
    @()
}

# 检查是否支持 Get-Cimresult
$isSupportCim = [bool](Get-Command Get-Cimresult -ErrorAction SilentlyContinue)

# 构造查询参数
$queryParams = @{ Namespace = $Namespace }
if ($isSupportCim) { $queryParams.ClassName = $Class } else { $queryParams.Class = $Class }
if ($Filter) { $queryParams.Filter = $Filter }

# 限制查询属性，加快查询速度
# CIM 支持
# WIM 不支持
if ($isSupportCim -and $propertyList.Count -gt 0) {
    $queryParams.Property = $propertyList
}

# 执行查询
$results = if ($isSupportCim) { Get-Cimresult @queryParams } else { Get-WmiObject @queryParams }

# 遍历结果
foreach ($result in $results) {
    # 遍历属性
    foreach ($property in $result.PSObject.Properties) {
        $name = $property.Name
        $value = $property.Value

        # 过滤系统属性
        if ($name.StartsWith("__") -or $name -eq "CimresultProperties" -or $name -eq "CimClass") { continue }

        # 只输出 propertyList 有的属性
        # propertyList 为空表示不过滤
        if ($propertyList.Count -eq 0 -or $propertyList -contains $name) {

            # 改成 wmic 的输出格式
            # 这里要注意 string 也是 IEnumerable
            if ($value -isnot [string] -and $value -is [Collections.IEnumerable]) {
                $formattedValue = ($value | ForEach-Object { "`"$_`"" }) -join ","
                Write-Output "$name={$formattedValue}"
            }
            else {
                Write-Output "$name=$value"
            }
        }
    }
}
