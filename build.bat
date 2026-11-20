@echo off
rem Shortcut: build.bat [debug|release] is viewertool build.
rem Every other step: odin run tools/viewertool -collection:gt=ext/gui_toolkit/src -out:build/viewertool -- <command> (help lists them).
cd /d "%~dp0"
if not exist build mkdir build
odin run tools/viewertool -collection:gt=ext/gui_toolkit/src -out:build/viewertool -keep-executable -- build %*
