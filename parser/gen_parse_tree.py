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
        result = trim_tree(tree, parser.ruleNames)
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
    exclude = [";", "<EOF>", "}"]
    return token_text in exclude


def is_allowable(rule_name):
    allow = ["crate", "item", "visItem"]
    return rule_name in allow


def get_pattern_id(node, rule_names):
    if rule_names[node.getRuleIndex()] == "identifier":
        return node.getChild(0)
    else:
        return get_pattern_id(node.getChild(0), rule_names)


def get_fn_params(node, rule_names):
    out = []
    for i in range(0, node.getChildCount(), 2):
        param = node.getChild(i)
        id = get_pattern_id(param.getChild(0), rule_names).getSymbol()
        out.append({"nam": id.text, "type": param.getChild(2)})

    return out


def is_expr_operator(node):
    # Prefix
    borrow = ["&", "&&"]
    borrow_attr = ["", "mut", "raw const", "raw mut"]
    deref = ["*"]
    neg = ["!", "-"]

    # Infix
    comp = ["==", "!=", ">", "<", ">=", "<="]
    arith = ["+", "-", "*", "/", "%", "^", "|", "&", "<<", ">>"]
    lazy_bool = ["||", "&&"]
    type_cast = ["as"]
    # TODO: CompoundAssignmentExpression (e.g. +=, *=, ...)

    # Postfix
    question = ["?"]

    infix = node.getChild(2)

    return infix in comp


def trim_expr(node, rule_names):
    rule_name = rule_names[node.getRuleIndex()]
    if rule_name == "expression":
        pass
    elif rule_name == "assignmentExpression":
        assign = ["="]
        pass
    elif rule_name == "literalExpression":
        return {"tag": "lit", "val": node.getChild(0).getSymbol().text}
    elif rule_name == "expressionWithBlock":
        # WARN: Circular recursion, BE CAREFUL!
        return trim_tree(node.getChild(0), rule_names)
    else:
        raise NotImplementedError("Expression type not implemented")


def trim_tree(node, rule_names):
    """
    Convert parse tree to structured JSON format including:
    - Syntactic structure (rules)
    - Token information (text, type)
    - Rust type (rule name from parser)
    """
    if isinstance(node, TerminalNode) and (not exclude_token(node.getSymbol().text)):
        token = node.getSymbol()
        raise AttributeError("don't want literals")
        return {
            "tag": "lit",
            "text": token.text,
            "token_type": RustLexer.symbolicNames[token.type],  # Token name
        }

    elif isinstance(node, ParserRuleContext):
        rule_name = rule_names[node.getRuleIndex()]

        if rule_name == "function_":
            fun_name = node.getChild(2).getChild(0).getSymbol().text
            params = get_fn_params(node.getChild(4), rule_names)
            return {
                "tag": "fun",
                "nam": fun_name,
                "params": params,
                "body": trim_tree(node.getChild(6), rule_names),
            }
        elif rule_name == "blockExpression":
            return {"tag": "blk", "body": trim_tree(node.getChild(1), rule_names)}
        elif rule_name == "statements":
            return {
                "tag": "seq",
                "stmts": [
                    trim_tree(node.getChild(i).getChild(0), rule_names)
                    for i in range(node.getChildCount())
                ],
            }
        elif rule_name == "expressionStatement":
            return trim_expr(node.getChild(0), rule_names)
        elif rule_name == "letStatement":
            pass
        elif rule_name == "macroInvocationSemi":
            raise NotImplementedError("Won't implement or macro statements")

        elif is_allowable(rule_name):
            children = [
                trim_tree(node.getChild(i), rule_names)
                for i in range(node.getChildCount())
            ]

            return {
                "rule": rule_name,  # Get rule name
                "rust_type": node.__class__.__name__,  # Class name (may indicate Rust type)
                "children": children,
            }
        else:
            raise NotImplementedError(f"Rule name {rule_name} not implemented in parse")

    return ""


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Choose Rust program to parse")
    parser.add_argument("-f", type=str, help="Filepath of file to be parsed")
    args = parser.parse_args()

    syntax_tree = parse_file(args.f)
    if syntax_tree:
        # NOTE: if multple files with same name but diff dir are parsed then silent conflict
        out_filename = (args.f.split("/")[-1]).split(".")[0]
        with open(f"../out_parse/{out_filename}.json", "w", encoding="utf-8") as f:
            print(syntax_tree)
            json.dump(syntax_tree, f, indent=2)
    else:
        print(f"ERROR response is not created {syntax_tree}")
