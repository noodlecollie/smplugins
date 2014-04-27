@echo off

REM I hate batch files.
REM This file is run after each compile and increments the plugin version define to save me having to do it myself.
REM This is a really brittle and stilted way to do it but as I said before, fuck batch files.

REM If the second parameter (the return of spcomp.exe) is not zero, exit from this script.
REM We don't want to increment the build number if the compile failed.
REM I told you this was hacky.
if %2 NEQ 0 (
    echo Compile failed, exiting.
    exit
)

setlocal ENABLEDELAYEDEXPANSION

REM This will get the build number and increment it.
FOR /F "tokens=3 delims= " %%x in (%1) DO (
    set /a buildno=%%x+1
    echo New build number: !buildno!
)

REM Write a text file with the new number.
set output=#define PLUGIN_BUILD !buildno!
echo !output!>%1

endlocal