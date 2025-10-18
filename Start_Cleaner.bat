@echo off
REM ========================================================================
REM File Cleaner Bot - Launcher
REM ========================================================================
REM Portable file cleanup utility with web interface
REM 
REM Authored and Architect: Sean Tabrizi
REM Email: seantab@gmail.com
REM ========================================================================

REM Store original directory
set "ORIGINAL_DIR=%CD%"

echo.
echo ========================================================================
echo File Cleaner Bot v2.0 (Portable) - Starting...
echo ========================================================================
echo.

cd /d "%~dp0"
powershell.exe -ExecutionPolicy Bypass -File "Cleaner.ps1"

echo.
echo File Cleaner Bot session ended.

REM Return to original directory
cd /d "%ORIGINAL_DIR%"
echo Returned to: %CD%
