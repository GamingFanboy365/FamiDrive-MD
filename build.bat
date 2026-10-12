@echo off
rem usage: build.bat [nes_rom]    (default: roms\nestest.nes)
set "ROM=%~f1"
cd /d "%~dp0"
if "%ROM%"=="" set "ROM=roms\nestest.nes"

if not exist "%ROM%" (
	echo build: %ROM% not found ^(see README^)
	exit /b 1
)
if not exist out mkdir out
copy /y "%ROM%" out\nes_rom.bin >nul

echo ** MEGA DRIVE **
tools\AS\win32\asw.exe md.asm -q -xx -c -A -olist out\rom_md.lst -A -L -D MCD=0,MARS=0,MARSCD=0
if errorlevel 1 exit /b 1
python tools\p2bin.py md.p out\rom_md.bin
if errorlevel 1 exit /b 1
del /q md.p md.h 2>nul
