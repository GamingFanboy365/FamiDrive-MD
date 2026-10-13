@echo off
rem usage: build.bat [--recompile] [nes_rom]    (default: roms\nestest.nes)
set RECOMP=0
if "%~1"=="--recompile" (
	set RECOMP=1
	shift
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
if %RECOMP%==1 (
	python tools\recomp6502.py out\nes_rom.bin out\recomp.asm
	if errorlevel 1 exit /b 1
)

echo ** MEGA DRIVE **
tools\AS\win32\asw.exe md.asm -q -xx -c -A -olist out\rom_md.lst -A -L -D MCD=0,MARS=0,MARSCD=0,RECOMP=%RECOMP%
if errorlevel 1 exit /b 1
python tools\p2bin.py md.p out\rom_md.bin
if errorlevel 1 exit /b 1
del /q md.p md.h 2>nul
