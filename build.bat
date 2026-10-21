@echo off
rem usage: build.bat [--recompile] [--fps] [nes_rom]    (default: roms\nestest.nes)
rem --fps adds a frames-per-second counter (needs --recompile)
set RECOMP=0
set FPS=0
:opts
if "%~1"=="--recompile" (
	set RECOMP=1
	shift
	goto opts
)
if "%~1"=="--fps" (
	set FPS=1
	shift
	goto opts
)
if %FPS%==1 if %RECOMP%==0 (
	echo build: --fps needs --recompile
	exit /b 1
)
set "ROM=%~f1"
cd /d "%~dp0"
if "%ROM%"=="" set "ROM=roms\nestest.nes"

if not exist "%ROM%" (
	echo build: %ROM% not found ^(see README^)
	exit /b 1
)
if not exist out mkdir out
copy /y "%ROM%" out\nes_rom.bin >nul
python tools\nesinfo.py out\nes_rom.bin out\nes_info.asm
if errorlevel 1 exit /b 1
if %RECOMP%==1 (
	python tools\recomp6502.py out\nes_rom.bin out\recomp.asm
	if errorlevel 1 exit /b 1
)

echo ** MEGA DRIVE **
tools\AS\win32\asw.exe md.asm -q -xx -c -A -olist out\rom_md.lst -A -L -D MCD=0,MARS=0,MARSCD=0,RECOMP=%RECOMP%,FPS=%FPS%
if errorlevel 1 exit /b 1
python tools\p2bin.py md.p out\rom_md.bin
if errorlevel 1 exit /b 1
del /q md.p md.h 2>nul
