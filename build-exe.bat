@echo off
setlocal

set "JANET_HOME=C:\Users\%USERNAME%\scoop\apps\janet\1.40.1"
set "JANET_HOME_FWD=C:/Users/%USERNAME%/scoop/apps/janet/1.40.1"
set "MINGW_HOME=C:\Users\%USERNAME%\scoop\apps\mingw\current"
set "JANET_BUILD_HOME=%JANET_HOME_FWD%"
set "PATH=%MINGW_HOME%\bin;%JANET_HOME%\bin;%PATH%"

"%JANET_HOME%\bin\janet.exe" build.janet
if errorlevel 1 exit /b %errorlevel%

set "PTHREAD_DLL_FOUND="
set "PTHREAD_DLL=%MINGW_HOME%\bin\libwinpthread-1.dll"
if not exist "%PTHREAD_DLL%" (
  for /f "delims=" %%F in ('where libwinpthread-1.dll 2^>nul') do (
    if not defined PTHREAD_DLL_FOUND set "PTHREAD_DLL_FOUND=%%F"
  )
  set "PTHREAD_DLL=%PTHREAD_DLL_FOUND%"
)

if exist "%PTHREAD_DLL%" (
  copy /Y "%PTHREAD_DLL%" "build\libwinpthread-1.dll" >nul
  copy /Y "%PTHREAD_DLL%" "libwinpthread-1.dll" >nul
) else (
  echo WARNING: libwinpthread-1.dll not found. Offline deployment must include it next to scada-keyboard.exe.
)
