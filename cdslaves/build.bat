@echo off
cd /D %~PD0
set CMDLINE=make -f makefile_cdslave.mak
set PROGNAME=JimPower
%CMDLINE%
goto end
set PROGNAME=Z-Out
%CMDLINE%
goto end
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
:end
pause
exit %X%
