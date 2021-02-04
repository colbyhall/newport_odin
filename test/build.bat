@echo off

set BASE_PATH="%~dp0"
cd %BASE_PATH%

if not exist bin mkdir bin

pushd bin

call odin build ..\src\ -out:test.exe -collection:newport=..\..\ -define:USE_VULKAN=true -debug

popd