@echo off

echo ======================================
echo        Automated Restore
echo ======================================
echo.

echo Initializing WinPE...
wpeinit

echo Waiting 5 seconds for storage initialization...
ping 127.0.0.1 -n 6 >nul

echo Searching all drives for Macrium image...
echo.

set IMAGECOUNT=0
set IMAGEFILE=

rem Search every normal drive letter except the WinPE X: drive.
for %%D in (C D E F G H I J K L M N O P Q R S T U V W Y Z) do call :scan_drive %%D

if %IMAGECOUNT% EQU 0 goto no_image
if %IMAGECOUNT% EQU 1 goto one_image

echo Found %IMAGECOUNT% backup images:
echo.
for /L %%I in (1,1,%IMAGECOUNT%) do call :show_image %%I
echo.

:select_image
set SELECTION=
set /p SELECTION=Select image [1-%IMAGECOUNT%]: 

if not defined SELECTION goto invalid_selection
for /f "delims=0123456789" %%A in ("%SELECTION%") do goto invalid_selection
if %SELECTION% LSS 1 goto invalid_selection
if %SELECTION% GTR %IMAGECOUNT% goto invalid_selection

call set "IMAGEFILE=%%IMAGE_%SELECTION%%%"
goto restore

:invalid_selection
echo Invalid selection.
echo.
goto select_image

:one_image
call set "IMAGEFILE=%%IMAGE_1%%"
goto restore

:no_image
echo ERROR: No .mrimg backup image was found.
echo Please verify that the drive containing the image is connected.
pause
goto finish

:restore
echo.
echo Selected image:
echo %IMAGEFILE%
echo.
echo Starting restore to Disk 0...

"X:\Program Files\Macrium\DiskRestore.exe" ^
    -r ^
    --imagefile "%IMAGEFILE%" ^
    --targetnum 0 ^
    -g ^
    -u ^
    --reboot

echo.
echo DiskRestore exited with error code %ERRORLEVEL%.
pause
goto finish

:scan_drive
if not exist "%1:\" goto :EOF
for /r %1:\ %%F in (*.mrimg) do call :add_image "%%F"
goto :EOF

:add_image
set /a IMAGECOUNT+=1
set "IMAGE_%IMAGECOUNT%=%~1"
set "IMAGENAME_%IMAGECOUNT%=%~nx1"
goto :EOF

:show_image
call set "DISPLAYNAME=%%IMAGENAME_%1%%"
echo [%1] %DISPLAYNAME%
goto :EOF

:finish
