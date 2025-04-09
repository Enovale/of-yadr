#!/bin/bash -e
cd "$(dirname "$0")"

test -e build || mkdir build

./spcomp64 -i "${SOURCEMOD_DIR}/scripting/include" -o build/yadr.smx scripting/yadr.sp

cp build/* "${SOURCEMOD_DIR}/plugins/"
