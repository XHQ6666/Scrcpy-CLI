@echo off
setlocal enabledelayedexpansion

rem 读取配置文件参数
set "config_file=%USERPROFILE%\scrcpy_config.json"

if exist "%config_file%" (
    for /f "usebackq delims=" %%A in (`powershell -NoProfile -ExecutionPolicy Bypass -Command "& { $p = '%config_file%'; if (-not (Test-Path $p)) { Write-Output '|'; exit 0 }; try { $c = Get-Content -Raw -Path $p | ConvertFrom-Json } catch { Write-Output '|'; exit 0 }; $s = if ($c.selected) { $c.selected } else { '' }; $d=''; $cam=''; if ($s -ne '') { $pr=$null; if ($c -ne $null) { if ($c.psobject.properties.name -contains 'profiles' -and $c.profiles.$s) { $pr = $c.profiles.$s } elseif ($c.psobject.properties.name -contains $s) { $pr = $c.$s } }; if ($pr -ne $null) { if ($pr.display_mirror) { $d = $pr.display_mirror }; if ($pr.camera_mirror) { $cam = $pr.camera_mirror } } }; Write-Output ($s + '|' + $d + '|' + $cam) }"`) do (
        for /f "tokens=1-3 delims=|" %%i in ("%%A") do (
            set "selected_profile=%%i"
            set "dsp_args=%%j"
            set "cam_args=%%k"
        )
    )
) else (
    set "selected_profile="
    set "dsp_args="
    set "cam_args="
)

:main_menu
set menu=
set choice=
set selected=
set cam=

cls
echo [Scrcpy 投屏]
echo.
echo 1. 屏幕镜像
echo 2. 相机镜像
echo 3. 麦克风音频
echo 4. 参数设置
echo 5. 退出
echo.
set /p menu=请输入选项编号：

if "%menu%" lss "1" (
    echo 输入无效，请重新选择。
    pause
    goto main_menu
)
if "%menu%" gtr "5" (
    echo 输入无效，请重新选择。
    pause
    goto main_menu
)

if "%menu%"=="1" set title=[屏幕镜像]
if "%menu%"=="2" set title=[相机镜像]
if "%menu%"=="3" set title=[麦克风音频]
if "%menu%"=="4" set title=[参数设置] & goto selected_config
if "%menu%"=="5" exit /b

cls
echo %title%
echo 正在检测设备...
echo.

set count=0
for /f "skip=1 tokens=1,2" %%i in ('adb devices') do (
    if NOT "%%i"=="" (
        set /a count+=1
        set "device[!count!]=%%i"
        set "status[!count!]=%%j"
    )
)

if "%count%"=="0" (
    echo 没有检测到已连接的设备！
    pause
    goto main_menu
)

if "%count%"=="1" (
    echo 检测到一个设备：!device[1]! 状态：!status[1]!
    echo 开始连接...
    timeout /t 2 /nobreak >nul
    set selected=!device[1]!
    goto menu_selection
)

echo 检测到%count%个设备，请选择：
for /l %%i in (1,1,%count%) do (
    set "label=[!status[%%i]!]"

    if /i "!status[%%i]!"=="device" set "label=[在线]"
    if /i "!status[%%i]!"=="unauthorized" set "label=[未授权]"
    if /i "!status[%%i]!"=="offline" set "label=[离线]"

    echo %%i. !device[%%i]! !label!
)

set /p choice=请输入设备编号：

if not defined device[%choice%] (
    echo 输入无效，返回主菜单
    pause
    goto main_menu
)

set "selected=!device[%choice%]!"
set "selected_status=!status[%choice%]!"

if /i "%selected_status%"=="offline" (
    echo 设备为离线状态，尝试重新连接...
    adb disconnect %selected%
    adb connect %selected%
    echo 已尝试重新连接，请检查设备是否在线
    pause
    goto main_menu
)

:menu_selection
if "%menu%"=="1" goto display_mirror
if "%menu%"=="2" goto cam_mirror
if "%menu%"=="3" goto mic_audio

:display_mirror
cls
echo %title%
scrcpy -s %selected% %dsp_args%
goto main_menu

:cam_mirror
cls
echo %title%
echo.

set /p cam=选择摄像头 (输入 b 返回): 
if "%cam%"=="1" ( set "cam_direction=flip90" ) else ( set "cam_direction=90" ) & if "%cam%"=="b" ( goto main_menu )
scrcpy -s %selected% --video-source=camera --camera-id=%cam% %cam_args% --display-orientation=%cam_direction%
goto main_menu

:mic_audio
cls
echo %title%
scrcpy -s %selected% --audio-source=mic --no-video
goto main_menu

:selected_config
cls
echo %title%
echo.
echo 当前配置：%selected_profile%
echo.
echo 可用配置：
set i=0
for /f "usebackq delims=" %%P in (`powershell -NoProfile -ExecutionPolicy Bypass -Command "if (Test-Path '%config_file%') { $c = Get-Content -Raw '%config_file%' | ConvertFrom-Json; if ($c -and $c.psobject.properties.name -contains 'profiles') { $c.profiles.psobject.properties | ForEach-Object { $_.Name } } else { $c.psobject.properties | Where-Object { $_.Name -ne 'selected' } | ForEach-Object { $_.Name } } }"`) do (
    set /a i+=1
    set "profile[!i!]=%%P"
    echo !i!. %%P
)

if "%i%"=="0" (
    echo 未发现可用配置。
    pause
    goto main_menu
)

set /p choice=请输入配置编号（回车取消）：
if "%choice%"=="" goto main_menu

if not defined profile[%choice%] (
    echo 输入无效，返回配置菜单
    pause
    goto selected_config
)

set "selected_profile=!profile[%choice%]!"

rem 将选择写回配置文件的 selected 字段
powershell -NoProfile -ExecutionPolicy Bypass -Command "try { $p = '%config_file%'; $c = Get-Content -Raw $p | ConvertFrom-Json; $c.selected = '%selected_profile%'; $c | ConvertTo-Json -Depth 10 | Set-Content -Path $p } catch {}"

rem 重新读取选中配置对应的 dsp_args 和 cam_args
for /f "usebackq delims=" %%A in (`powershell -NoProfile -ExecutionPolicy Bypass -Command "try { $c = Get-Content -Raw '%config_file%' | ConvertFrom-Json; $s = if ($c.selected) { $c.selected } else { '' }; $d=''; $cam=''; if ($s -ne '') { $pr=$null; if ($c -ne $null) { if ($c.psobject.properties.name -contains 'profiles' -and $c.profiles.$s) { $pr = $c.profiles.$s } elseif ($c.psobject.properties.name -contains $s) { $pr = $c.$s } }; if ($pr -ne $null) { if ($pr.display_mirror) { $d = $pr.display_mirror }; if ($pr.camera_mirror) { $cam = $pr.camera_mirror } } }; Write-Output ($s + '|' + $d + '|' + $cam) } catch { Write-Output '|' }"`) do (
    for /f "tokens=1-3 delims=|" %%i in ("%%A") do (
        set "selected_profile=%%i"
        set "dsp_args=%%j"
        set "cam_args=%%k"
    )
)

echo 已选择：%selected_profile%
pause
goto main_menu