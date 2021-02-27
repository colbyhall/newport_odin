@echo off

set BASE_PATH="%~dp0"
cd %BASE_PATH%

if not exist bin mkdir bin

pushd bin

if exist *.exe del *.exe

call odin build ..\src\ -out:test.exe -collection:newport=..\..\ -define:USE_VULKAN=true -debug

if exist test.exe (
    if "%1" == "-run" call test.exe
    if "%1" == "-r" call test.exe
)

popd

