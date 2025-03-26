Parser and Lexer generated from https://github.com/antlr/grammars-v4

To recreate the generation, follow the following steps:

1. Clone the directory of the language we want to parse (i.e. grammers-v4/rust)
2. Copy any files from the directory after the target (In this case, python) to the root dir of the grammer
3. Run `transformGRammars.py`
4. Run `antlr4 -Dlanguage=Python3 RustLexer.g4 RustParser.g4`
5. Test using `python3 testing_script.py`
