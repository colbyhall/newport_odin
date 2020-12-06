@echo off

set BASE_PATH="%~dp0"
cd %BASE_PATH%

if not exist build mkdir build
if not exist data mkdir data

pushd build

call odin build ..\src\test.odin -collection:newport=..\..\ -debug

popd