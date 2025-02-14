#!/bin/bash

if [[ "$1" = "-d" ]]; then
	git clone https://github.com/antlr/antlr4.git
elif [[ "$1" = "-h" ]]; then
	echo "run script to install make and install. run with '-d' to also git clone the antlr repo"
fi
	

ANTLR_PATH="$(pwd)/antlr4"
# instructions in readme <https://github.com/antlr/antlr4/tree/dev/runtime/Cpp>

cd "$ANTLR_PATH/runtime/Cpp" || { echo "Directory not found!"; exit 1; }
mkdir -p build && mkdir -p run && cd build

cmake ..
make
DESTDIR="$ANTLR_PATH/runtime/Cpp/run" make install

