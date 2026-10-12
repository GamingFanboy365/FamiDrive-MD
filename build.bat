@echo off
cd /d "%~dp0"

if not exist roms\nestest.nes (
	echo build: roms\nestest.nes not found ^(see README^)
	exit /b 1
)
if not exist out mkdir out

echo ** MEGA DRIVE **
tools\AS\win32\asw.exe md.asm -q -xx -c -A -olist out\rom_md.lst -A -L -D MCD=0,MARS=0,MARSCD=0
if errorlevel 1 exit /b 1
python tools\p2bin.py md.p out\rom_md.bin
if errorlevel 1 exit /b 1
del /q md.p md.h 2>nul
