@echo off

pushd ..\

echo Setting up Newport

call setup.bat

popd

if not exist bin mkdir bin

echo Copying required dll's

copy /B ..\deps\dxc\dxcompiler.dll bin\dxcompiler.dll

