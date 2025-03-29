from antlr4 import *
from RustLexer import RustLexer
from RustParser import RustParser
from antlr4.tree.Tree import TerminalNode

import traceback
import argparse
import json
from io import StringIO


def parse_file(filepath):
    inputstream = FileStream(filepath, encoding="utf-8")
    output = StringIO()
    lexer = RustLexer(inputstream, output)
    tokenstream = CommonTokenStream(lexer)
    parser = RustParser(tokenstream, output)

    result = None
    try:
        tree = parser.crate()
        print(tree.toStringTree(parser.ruleNames))
        result = to_json(tree, parser.ruleNames)
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


def exclude_token(token_text):
    exclude = [";"]
    return token_text in exclude


def is_allowable(rule_name):
    allow = ["crate"]
    return rule_name in allow


def to_json(node, rule_names):
    """
    Convert parse tree to structured JSON format including:
    - Syntactic structure (rules)
    - Token information (text, type)
    - Rust type (rule name from parser)
    """
    rule_name = rule_names[node.getRuleIndex()]
    if isinstance(node, TerminalNode) and (not exclude_token(node.getSymbol().text)):
        token = node.getSymbol()
        return {
            "tag": "lit",
            "text": token.text,
            "token_type": RustLexer.symbolicNames[token.type],  # Token name
        }

    elif isinstance(node, ParserRuleContext):
        if rule_name == "let":
            pass

        elif is_allowable(rule_name):
            children = [
                to_json(node.getChild(i), rule_names)
                for i in range(node.getChildCount())
            ]

            return {
                "rule": rule_name,  # Get rule name
                "rust_type": node.__class__.__name__,  # Class name (may indicate Rust type)
                "children": children,
            }
        else:
            raise NotImplementedError(f"Rule name {rule_name} not implemented in parse")
            # children = [
            #     to_json(node.getChild(i), rule_names) for i in range(node.getChildCount())
            # ]
            #
            # return {
            #     "rule": rule_name,  # Get rule name
            #     "rust_type": node.__class__.__name__,  # Class name (may indicate Rust type)
            #     "children": children,
            # }

    return None


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Choose Rust program to parse")
    parser.add_argument("-f", type=str, help="Filepath of file to be parsed")
    args = parser.parse_args()

    syntax_tree = parse_file(args.f)
    if syntax_tree:
        # NOTE: if multple files with same name but diff dir are parsed then silent conflict
        out_filename = (args.f.split("/")[-1]).split(".")[0]
        with open(f"../out_parse/{out_filename}.json", "w", encoding="utf-8") as f:
            json.dump(syntax_tree, f, indent=2)
    else:
        print(f"ERROR response is not created {syntax_tree}")
