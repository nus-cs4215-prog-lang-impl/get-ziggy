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


def get_call_params(all_args, rule_names):
    args = []
    for a in range(0, all_args.getChildCount(), 2):
        args.append(trim_expr(all_args.getChild(a), rule_names))
    return args


def expr_pre_post_operator(node):
    # Prefix
    borrow = ["&", "&&"]
    borrow_attr = ["", "mut", "raw const", "raw mut"]

    deref = ["*"]
    neg = ["!", "-"]

    # Postfix
    question = ["?"]

    return (1, 1, 1)


def expr_infix_operator(node):
    # Infix
    comp = ["==", "!=", ">", "<", ">=", "<="]
    arith = ["+", "-", "*", "/", "%", "^", "|", "&", "<<", ">>"]
    lazy_bool = ["||", "&&"]
    type_cast = ["as"]
    # NOTE: antlr treats 'assignmentExpression' (from Rust grammar) as regular expr
    assign = ["="]
    # TODO: CompoundAssignmentExpression (e.g. +=, *=, ...)
    compound_assign = ["+=", "-=", "*=", "/=", "%=", "&=", "|=", "^=", "<<=", ">>="]

    op = node.getChild(1)
    # assert isinstance(op, TerminalNode), "operator is not TerminalNode"
    if not isinstance(op, TerminalNode):
        assert isinstance(
            op.getChild(0), TerminalNode
        ), "Assertion: op needs to be at most one layer deep"

        infix = op.getChild(0).getSymbol().text
    else:
        infix = op.getSymbol().text

    op_type = ""

    if infix in arith:
        op_type = "arith"
    elif infix in comp:
        op_type = "comp"
    elif infix in lazy_bool:
        op_type = "logic"
    elif infix in type_cast:
        op_type = "typecast"
    elif infix in assign:
        op_type = "assign"
    elif infix in compound_assign:
        op_type = "compound_assign"
    else:
        raise NotImplementedError(f"infix op:::{infix}:::not implemented")

    return infix, op_type, node.getChild(0), node.getChild(2)


# TODO: for trimmming expr
# 1. prefix expr
# 2. grouped expressions
# 3. block expressions
# 4. if expressions
def trim_expr(node, rule_names):
    rule_name = rule_names[node.getRuleIndex()]

    if rule_name == "expression":
        # NOTE: Heurisitc used for finding call expression as antlr tree
        # does not yield call expression tag
        assert node.getChildCount() >= 1, "'expression' tag has less than 1 children"

        if isinstance(node.getChild(0), TerminalNode) and node.getChild(
            0
        ).getSymbol().text in ["return", "break", "continue"]:
            return {
                "tag": node.getChild(0).getSymbol().text,
                "body": (
                    None
                    if node.getChildCount() != 2
                    else trim_expr(node.getChild(1), rule_names)
                ),
            }
        elif (
            node.getChildCount() >= 3
            and node.getChild(0)
            and isinstance(node.getChild(1), TerminalNode)
            and node.getChild(1).getSymbol().text == "("
        ):
            fn_name = trim_expr(node.getChild(0), rule_names)
            return {
                "tag": "app",
                "nam": fn_name,
                "args": get_call_params(node.getChild(2), rule_names),
            }

        elif node.getChildCount() == 3:
            # NOTE: Check footnote on precendence
            op, op_type, lhs, rhs = expr_infix_operator(node)
            return {
                "tag": op_type,
                "sym": op,
                "first": trim_expr(lhs, rule_names),
                "second": trim_expr(rhs, rule_names),
            }
        elif node.getChildCount() == 2:
            op, op_type, lhs = expr_pre_post_operator(node)
            return {
                "tag": op_type,
                "sym": op,
                "first": trim_expr(lhs, rule_names),
            }
        else:
            return trim_expr(node.getChild(0), rule_names)

    elif rule_name == "pathExpression":
        path = node.getChild(0)
        assert path.getChildCount() == 1, "Var name path must be of len 1"
        return path.getChild(0).getChild(0).getChild(0).getChild(0).getSymbol().text

    elif rule_name == "literalExpression":
        return {"tag": "lit", "val": node.getChild(0).getSymbol().text}

    elif rule_name == "expressionWithBlock":
        raise NotImplementedError("implement a return hatch")
        # WARN: Circular recursion, BE CAREFUL!
        # return trim_tree(node.getChild(0), rule_names)

    else:
        raise NotImplementedError("Expression type not implemented")


# TODO: deal with identifiers properly
def trim_tree(node, rule_names):
    """
    Convert parse tree to structured JSON format including:
    - Syntactic structure (rules)
    - Token information (text, type)
    - Rust type (rule name from parser)
    """
    if isinstance(node, TerminalNode) and (not exclude_token(node.getSymbol().text)):
        token = node.getSymbol()
        raise AttributeError(f"don't want literals:::::{token.text}::::")
        return {
            "tag": "lit",
            "text": token.text,
            "token_type": RustLexer.symbolicNames[token.type],  # Token name
        }

    elif isinstance(node, ParserRuleContext):
        rule_name = rule_names[node.getRuleIndex()]

        # TODO: return type
        if rule_name == "function_":
            fun_name = node.getChild(2).getChild(0).getSymbol().text

            para_node = node.getChild(4)
            if isinstance(para_node, TerminalNode):
                params = []
                body = trim_tree(node.getChild(5), rule_names)
            else:
                params = get_fn_params(para_node, rule_names)
                body = trim_tree(node.getChild(6), rule_names)

            return {"tag": "fun", "nam": fun_name, "params": params, "body": body}
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
        elif rule_name == "expressionStatement" or rule_name == "expression":
            return trim_expr(node.getChild(0), rule_names)
        elif rule_name == "letStatement":
            assert node.getChildCount() == 5
            lhs_node = node.getChild(1).getChild(0).getChild(0)
            if isinstance(lhs_node.getChild(0), TerminalNode):
                is_mut = True
                nam = lhs_node.getChild(1).getChild(0).getSymbol().text
            else:
                is_mut = False
                nam = lhs_node.getChild(0).getChild(0).getSymbol().text

            rhs_node = trim_tree(node.getChild(3), rule_names)
            return {
                "tag": "assign",
                "is_mut": is_mut,
                "nam": nam,
                "val": rhs_node,
            }
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


#
#
# NOTE: FOOTNOTE
# - Operator precendence We don't impl
# ---- We don't do it, cause the antlr parse tree is left to right recursive
# (expression
#     (expression (identifier y)) +
#         (expression
#             (expression
#                 (expression (literalExpression 1))
#                 *
#                 (expression (literalExpression 2)))
#                     / (expression (literalExpression 5))
#         )
# )
