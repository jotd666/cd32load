@echo off
cd /D %~PD0
set CMDLINE=C:\SysGCC\arm-eabi\bin\make -f makefile_cdslave.mak
set PROGNAME=MarbleMadness
%CMDLINE%
set PROGNAME=Gods
%CMDLINE%
set X=%ERRORLEVEL%
set PROGNAME=Wonderdog
%CMDLINE%
set X=%ERRORLEVEL%
set PROGNAME=Lemmings
%CMDLINE%
set X=%ERRORLEVEL%
set PROGNAME=Silkworm
%CMDLINE%
set X=%ERRORLEVEL%
set PROGNAME=Premiere
%CMDLINE%
set X=%ERRORLEVEL%
pause
exit %X%
