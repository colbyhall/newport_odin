@echo off

echo Grabbing submodules
call git submodule init
call git submodule update

pushd deps\spirv_reflect

echo Building SPIRV Reflect
call build.bat

popd
pushd deps\stb\src

echo Building stb
call build.bat

popd


