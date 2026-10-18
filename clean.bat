@echo off
rem cleans this project back to what is in git: empties the build and logs folders, and deletes the nex file, the
rem SD card images, the last build.log, ZEsarUX's menu index, and any <project>.bin or <project>test.bin left here...
rem N.B: whatever the program saved on a card goes with the card, the next build makes everything again
setlocal
cd /d "%~dp0"
for %%I in (.) do set NAME=%%~nxI
if exist build ( rmdir /s /q build & mkdir build )
if exist logs  ( rmdir /s /q logs  & mkdir logs  )
rem /f, as the base card is kept read-only
del /f /q *.mmc                 2>nul
del /q %NAME%.nex               2>nul
del /q %NAME%*.bin              2>nul
del /q zesarux_index_menu.idx   2>nul
del /q build.log                2>nul
echo %NAME% cleaned
exit /b
