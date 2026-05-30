@echo off
setlocal enabledelayedexpansion

rem Read config file arguments
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
set call_choice=
set call_audio_source=

cls
echo [Scrcpy Mirroring]
echo.
echo 1. Screen Mirroring
echo 2. Camera Mirroring
echo 3. Microphone Audio
echo 4. Call Audio
echo 5. Settings
echo 6. Exit
echo.
set /p menu=Enter option number: 

if "%menu%" lss "1" (
    echo Invalid input. Please select again.
    pause
    goto main_menu
)
if "%menu%" gtr "6" (
    echo Invalid input. Please select again.
    pause
    goto main_menu
)

if "%menu%"=="1" set title=[Screen Mirroring]
if "%menu%"=="2" set title=[Camera Mirroring]
if "%menu%"=="3" set title=[Microphone Audio]
if "%menu%"=="4" set title=[Call Audio]
if "%menu%"=="5" set title=[Settings] & goto selected_config
if "%menu%"=="6" exit /b

cls
echo %title%
echo Detecting devices...
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
    echo No connected devices detected.
    pause
    goto main_menu
)

if "%count%"=="1" (
    echo Detected one device: !device[1]! status: !status[1]!
    echo Connecting...
    timeout /t 2 /nobreak >nul
    set selected=!device[1]!
    goto menu_selection
)

echo Detected %count% devices. Please select one:
for /l %%i in (1,1,%count%) do (
    set "label=[!status[%%i]!]"

    if /i "!status[%%i]!"=="device" set "label=[online]"
    if /i "!status[%%i]!"=="unauthorized" set "label=[unauthorized]"
    if /i "!status[%%i]!"=="offline" set "label=[offline]"

    echo %%i. !device[%%i]! !label!
)

set /p choice=Enter device number: 

if not defined device[%choice%] (
    echo Invalid input, returning to main menu.
    pause
    goto main_menu
)

set "selected=!device[%choice%]!"
set "selected_status=!status[%choice%]!"

if /i "%selected_status%"=="offline" (
    echo Device is offline. Attempting to reconnect...
    adb disconnect %selected%
    adb connect %selected%
    echo Reconnect attempted. Please check whether the device is online.
    pause
    goto main_menu
)

:menu_selection
if "%menu%"=="1" goto display_mirror
if "%menu%"=="2" goto cam_mirror
if "%menu%"=="3" goto mic_audio
if "%menu%"=="4" goto call_audio

:display_mirror
cls
echo %title%
scrcpy -s %selected% %dsp_args%
goto main_menu

:cam_mirror
cls
echo %title%
echo.

set /p cam=Select camera ID (enter b to return): 
if "%cam%"=="1" ( set "cam_direction=flip90" ) else ( set "cam_direction=90" ) & if "%cam%"=="b" ( goto main_menu )
scrcpy -s %selected% --video-source=camera --camera-id=%cam% %cam_args% --display-orientation=%cam_direction%
goto main_menu

:mic_audio
cls
echo %title%
scrcpy -s %selected% --audio-source=mic --no-video
goto main_menu

:call_audio
cls
echo %title%
echo.
echo 1. Both Sides Audio
echo 2. Local Audio
echo 3. Remote Audio
echo.
set /p call_choice=Enter option number (Enter for both sides audio, b to return): 
if /i "%call_choice%"=="b" goto main_menu
if "%call_choice%"=="" set "call_audio_source=voice-call"
if "%call_choice%"=="1" set "call_audio_source=voice-call"
if "%call_choice%"=="2" set "call_audio_source=voice-call-downlink"
if "%call_choice%"=="3" set "call_audio_source=voice-call-uplink"
if not defined call_audio_source (
    echo Invalid input, returning to main menu.
    pause
    goto main_menu
)
scrcpy -s %selected% --audio-source=%call_audio_source% --no-video
goto main_menu

:selected_config
cls
echo %title%
echo.
echo Current profile: %selected_profile%
echo.
echo Available profiles:
set i=0
for /f "usebackq delims=" %%P in (`powershell -NoProfile -ExecutionPolicy Bypass -Command "if (Test-Path '%config_file%') { $c = Get-Content -Raw '%config_file%' | ConvertFrom-Json; if ($c -and $c.psobject.properties.name -contains 'profiles') { $c.profiles.psobject.properties | ForEach-Object { $_.Name } } else { $c.psobject.properties | Where-Object { $_.Name -ne 'selected' } | ForEach-Object { $_.Name } } }"`) do (
    set /a i+=1
    set "profile[!i!]=%%P"
    echo !i!. %%P
)

if "%i%"=="0" (
    echo No available profiles found.
    pause
    goto main_menu
)

set /p choice=Enter profile number (press Enter to cancel): 
if "%choice%"=="" goto main_menu

if not defined profile[%choice%] (
    echo Invalid input, returning to settings menu.
    pause
    goto selected_config
)

set "selected_profile=!profile[%choice%]!"

rem Write the selected profile to the selected field in the config file
powershell -NoProfile -ExecutionPolicy Bypass -Command "try { $p = '%config_file%'; $c = Get-Content -Raw $p | ConvertFrom-Json; $c.selected = '%selected_profile%'; $c | ConvertTo-Json -Depth 10 | Set-Content -Path $p } catch {}"

rem Reload dsp_args and cam_args for the selected profile
for /f "usebackq delims=" %%A in (`powershell -NoProfile -ExecutionPolicy Bypass -Command "try { $c = Get-Content -Raw '%config_file%' | ConvertFrom-Json; $s = if ($c.selected) { $c.selected } else { '' }; $d=''; $cam=''; if ($s -ne '') { $pr=$null; if ($c -ne $null) { if ($c.psobject.properties.name -contains 'profiles' -and $c.profiles.$s) { $pr = $c.profiles.$s } elseif ($c.psobject.properties.name -contains $s) { $pr = $c.$s } }; if ($pr -ne $null) { if ($pr.display_mirror) { $d = $pr.display_mirror }; if ($pr.camera_mirror) { $cam = $pr.camera_mirror } } }; Write-Output ($s + '|' + $d + '|' + $cam) } catch { Write-Output '|' }"`) do (
    for /f "tokens=1-3 delims=|" %%i in ("%%A") do (
        set "selected_profile=%%i"
        set "dsp_args=%%j"
        set "cam_args=%%k"
    )
)

echo Selected: %selected_profile%
pause
goto main_menu
