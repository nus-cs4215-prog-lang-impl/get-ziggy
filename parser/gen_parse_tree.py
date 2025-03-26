from antlr4 import *
from io import StringIO
from RustLexer import RustLexer
from RustParser import RustParser
import traceback
import argparse
import json


def parse_file(filepath):
    inputstream = FileStream(filepath, encoding="utf-8")
    output = StringIO()
    lexer = RustLexer(inputstream, output)
    tokenstream = CommonTokenStream(lexer)
    parser = RustParser(tokenstream, output)

    result = None
    try:
        tree = parser.crate()
        print(tree.toStringTree())
        result = to_json(tree)
    except Exception as e:
        output.write("\n" * 2)
        output.write(" *" * 10)
        output.write(" EXCEPTION ")
        output.write("* " * 20)
        output.write(str(e))
        output.write("\n")
        traceback.print_exc(file=output)
        output.write("\n" * 2)
        print(f"exception {e}")

    return result


def to_json(tree):
    # Convert parse tree to JSON
    def traverse(node):
        if isinstance(node, TerminalNode):
            return {
                "text": str(node),
                "type": "TerminalNode",
                "children": [],
            }
        else:
            children = []
            for i in range(node.getChildCount()):
                children.append(traverse(node.getChild(i)))

            node_text = node.getText()
            try:
                node_type = node.getType()
            except:
                node_type = "undefined"

            return {
                "text": node_text,
                "type": node_type,
                "children": children,
            }

    return json.dumps(traverse(tree), indent=2)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Choose Rust program to parse")
    parser.add_argument("--filepath", type=str, help="Filepath of file to be parsed")
    args = parser.parse_args()

    res = parse_file(args.filepath)
    if res:
        with open(f"./parsed_hiii.json", "w") as f:
            f.write(res)
    else:
        print(f"ERROR response is not created {res}")
