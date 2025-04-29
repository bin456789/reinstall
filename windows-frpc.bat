@echo off
mode con cp select=437 >nul

rem Windows Deferder 会误报，因此要添加白名单
powershell -ExecutionPolicy Bypass -Command "Add-MpPreference -ExclusionPath '%SystemDrive%\frpc\frpc.exe'"

rem 启用日志
rem wevtutil set-log Microsoft-Windows-TaskScheduler/Operational /enabled:true

rem 创建计划任务并立即运行
schtasks /Create /TN "frpc" /XML "%SystemDrive%\frpc\frpc.xml"
schtasks /Run /TN "frpc"
del "%SystemDrive%\frpc\frpc.xml"

rem win10+ 在首次登录后计划任务才生效
rem 即使手动重启，计划任务也没有运行

rem 如果 10 秒内有 frpc 进程，则代表计划任务已经生效，不需要首次登录
rem 如果 10 秒后也没有 frpc 进程，则需要临时改用 SYSTEM 用户运行计划任务
for /L %%i in (1,1,10) do (
    timeout 1
    tasklist /FI "IMAGENAME eq frpc.exe" | find /I "frpc.exe" && (
        goto :end
    )
)

rem 临时改用 SYSTEM 用户运行计划任务，运行后再改回 Local Service 用户
schtasks /Change /TN "frpc" /RU "S-1-5-18"
schtasks /Run /TN "frpc"
schtasks /Change /TN "frpc" /RU "S-1-5-19"

:end
rem 删除此脚本
del "%~f0"
