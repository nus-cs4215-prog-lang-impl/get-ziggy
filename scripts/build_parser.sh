#!/bin/bash

echo "We require python version 3.12, your version is $(python --version)"

cd ../parser
# Steps taken from antlr4 readme
# <>

python transformGRammars.py

antlr4 -Dlanguage=Python3 RustLexer.g4 RustParser.g4

python testing_script.py
