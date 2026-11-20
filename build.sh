#!/usr/bin/env bash
# Shortcut: ./build.sh [debug|release] is viewertool build.
# Every other step: odin run tools/viewertool -collection:gt=ext/gui_toolkit/src -out:build/viewertool -- <command> (help lists them).
cd "$(dirname "$0")" && mkdir -p build && exec odin run tools/viewertool -collection:gt=ext/gui_toolkit/src -out:build/viewertool -keep-executable -- build "$@"
