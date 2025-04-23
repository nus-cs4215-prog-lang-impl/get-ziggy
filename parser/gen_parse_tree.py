#! /usr/bin/env python3
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
    allow = ["item", "visItem"]
    return rule_name in allow


def get_pattern_id(node, rule_names):
    if rule_names[node.getRuleIndex()] == "identifier":
        return node.getChild(0)
    else:
        return get_pattern_id(node.getChild(0), rule_names)


def get_fn_params(node, rule_names):
    out = []
    for i in range(0, node.getChildCount(), 2):
        param = node.getChild(i).getChild(0)
        assert (
            param.getChildCount() == 3
        ), "Assertion: Function parameters must be explicitly typed (totalling in 3 items)"
        id = get_pattern_id(param, rule_names).getSymbol()
        out.append({"nam": id.text, "type_name": trim_type(param.getChild(2), rule_names)})

    return out


def get_call_params(all_args, rule_names):
    args = []
    for a in range(0, all_args.getChildCount(), 2):
        args.append(trim_expr(all_args.getChild(a), rule_names))
    return args


def expr_pre_post_operator(node):
    # Prefix
    borrow = ["&", "&&"]
    # NOTE: Don't support 'raw mut' or 'const mut' as they are macros
    borrow_attr = ["mut"]

    deref = ["*"]
    neg = ["!", "-"]

    # Postfix
    question = ["?"]

    op_type = ""
    if isinstance(node.getChild(0), TerminalNode):
        op = node.getChild(0).getSymbol().text
        if node.getChildCount() > 2:
            expr = node.getChild(2)

            attr = node.getChild(1).getSymbol().text
            if op in borrow and attr in borrow_attr:
                op_type = "borrow_mut"

        else:
            expr = node.getChild(1)

            if op in borrow:
                op_type = "borrow"
            elif op in deref:
                op_type = "deref"
            elif op in neg:
                op_type = "neg"
    else:
        op = node.getChild(1).getSymbol().text
        expr = node.getChild(0)

        if op in question:
            op_type = "question"

    if op_type == "":
        raise NotImplementedError("Assertion: Type of unary operator not implemented")

    return op, op_type, expr


def expr_infix_operator(node):
    # Infix
    comp = ["==", "!=", ">", "<", ">=", "<="]
    arith = ["+", "-", "*", "/", "%", "^", "|", "&", "<<", ">>"]
    lazy_bool = ["||", "&&"]
    type_cast = ["as"]
    # NOTE: antlr treats 'assignmentExpression' (from Rust grammar) as regular expr
    assign = ["="]
    compound_assign = ["+=", "-=", "*=", "/=", "%=", "&=", "|=", "^=", "<<=", ">>="]

    op = node.getChild(1)
    infix = None
    if op.getChildCount() == 1:
        infix = op.getChild(0).getSymbol().text
    elif op.getChildCount() == 0:
        infix = op.getSymbol().text
    else:
        raise AttributeError("Assertion: op needs to be 0,1 or 3 layers deep")

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
        op_type = "reassign"
    elif infix in compound_assign:
        op_type = "compound_assign"
    else:
        raise NotImplementedError(f"infix op:::{infix}:::not implemented")

    return infix, op_type, node.getChild(0), node.getChild(2)


def trim_expr(node, rule_names):
    rule_name = rule_names[node.getRuleIndex()]

    if rule_name == "expression":
        # NOTE: Heurisitc used for finding call expression as antlr tree
        # does not yield call expression tag
        assert (
            node.getChildCount() >= 1
        ), "Assertion: 'expression' tag has less than 1 children"

        if isinstance(node.getChild(0), TerminalNode) and node.getChild(
            0
        ).getSymbol().text in ["return", "break", "continue"]:
            return {
                f"{node.getChild(0)
                .getSymbol()
                .text}_statement": {
                    "body": (
                        None
                        if node.getChildCount() != 2
                        else trim_expr(node.getChild(1), rule_names)
                    ),
                }
            }
        elif (
            node.getChildCount() >= 3
            and node.getChild(0)
            and isinstance(node.getChild(1), TerminalNode)
            and node.getChild(1).getSymbol().text == "("
        ):
            fn_name = trim_expr(node.getChild(0), rule_names)
            return {
                "app": {
                    "nam": fn_name['nam'],
                    "args": get_call_params(node.getChild(2), rule_names),
                }
            }
        elif node.getChildCount() == 2 or (
            isinstance(node.getChild(0), TerminalNode)
            and node.getChild(0).getSymbol().text in ["&", "&&"]
        ):
            op, op_type, lhs = expr_pre_post_operator(node)
            return {
                op_type: {
                    "sym": op,
                    "first": trim_expr(lhs, rule_names),
                }
            }

        elif node.getChildCount() == 3:
            if (
                isinstance(node.getChild(0), TerminalNode)
                and node.getChild(0).getSymbol().text == "("
                and isinstance(node.getChild(2), TerminalNode)
                and node.getChild(2).getSymbol().text == ")"
            ):
                return trim_expr(node.getChild(1), rule_names)
            else:
                # NOTE: Check footnote on precendence
                op, op_type, lhs, rhs = expr_infix_operator(node)
                return {
                    op_type: {
                        "sym": op,
                        "first": trim_expr(lhs, rule_names),
                        "second": trim_expr(rhs, rule_names),
                    }
                }

        else:
            return trim_expr(node.getChild(0), rule_names)

    elif rule_name == "pathExpression":
        path = node.getChild(0)
        assert path.getChildCount() == 1, "Assertion: Var name path must be of len 1"
        return {
            "nam": path.getChild(0)
                .getChild(0)
                .getChild(0)
                .getChild(0)
                .getSymbol()
                .text,
        }

    elif rule_name == "literalExpression":
        val = node.getChild(0).getSymbol().text
        type_name = None

        if val == "true" or val == "false":
            type_name = "bool"
        elif val.startswith('"') and val.endswith('"'):
            type_name = "String"
        elif val.startswith("'") and val.endswith("'"):
            type_name = "String"
        elif "_" in val:
            parts = val.split("_", 1)
            if len(parts) == 2 and parts[0]: # Ensure there's a value before '_'
                val = parts[0]
                type_name = parts[1]
        elif "." in val:
            try:
                float(val) # Check if it's a valid float
                type_name = "f64" # Default float type
            except ValueError:
                pass # Or raise an error, or assign a default type
        elif val.isdigit():
            type_name = "i32" # Default integer type
        else:
            type_name = "String"

        return {"lit": {"val": val, "type_name": type_name}}


        return {"lit": {"val": val, "type_name": type_name}}

    elif rule_name == "expressionWithBlock":
        # WARN: Circular recursion, BE CAREFUL!
        return trim_tree(node.getChild(0), rule_names)

    elif rule_name == "expressionStatement":
        return trim_expr(node.getChild(0), rule_names)

    elif rule_name == "ifExpression":
        assert (
            node.getChildCount() == 3 or node.getChildCount() == 5
        ), "Assertion: :ifExpression can have only 3 of 5 children"

        return {
            "cond": {
                "pred": trim_expr(node.getChild(1), rule_names),
                "cons": trim_tree(node.getChild(2), rule_names),
                "alt": (
                    trim_tree(node.getChild(4), rule_names)
                    if node.getChildCount() == 5
                    else None
                ),
            }
        }
    elif rule_name == "loopExpression":
        loop = node.getChild(0)
        return {
            "while_loop": {
                "pred": trim_expr(loop.getChild(1), rule_names),
                "body": trim_tree(loop.getChild(2), rule_names),
            }
        }
    else:
        raise NotImplementedError(
            f"Assertion: Expression type:::{rule_name}:::not implemented"
        )


def trim_type(node, rule_names):
    rule_name = rule_names[node.getRuleIndex()]

    if rule_name == "type_":
        while rule_name != "identifier":
            assert node.getChildCount() == 1
            node = node.getChild(0)
            rule_name = rule_names[node.getRuleIndex()]
        return node.getChild(0).getSymbol().text

    else:
        raise NotImplementedError(f"Assertion: Type:::{rule_name}:::not implemented")


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
            "token_type": RustLexer.symbolicNames[token.type],  # Token name
        }

    elif isinstance(node, ParserRuleContext):
        rule_name = rule_names[node.getRuleIndex()]

        if rule_name == "function_":
            fun_name = node.getChild(2).getChild(0).getSymbol().text

            params = []
            rtn_type = None
            body = None
            for i in range(4, node.getChildCount()):
                child = node.getChild(i)
                if isinstance(child, TerminalNode):
                    continue
                rule = rule_names[child.getRuleIndex()]
                if rule == "functionParameters":
                    params = get_fn_params(child,rule_names)
                elif rule == "functionReturnType":
                    rtn_type = trim_type(child.getChild(1), rule_names)
                elif rule == "blockExpression":
                    body = trim_tree(child.getChild(1), rule_names)

            body = None if body == "" else body

            return {"fun": {"nam": fun_name, "params": params, "return_type": rtn_type, "body": body}}

        elif rule_name == "blockExpression":
            return {"blk": {"body": trim_tree(node.getChild(1), rule_names)}}

        elif rule_name == "statements":
            all = []
            for i in range(node.getChildCount()):
                stmt = trim_tree(node.getChild(i), rule_names)
                if stmt != "":
                    all.append(stmt)
            return {"seq": {"stmts": all}}

        elif rule_name == "statement":
            assert node.getChildCount() == 1, "Assertion: Statement has 1 child"
            return trim_tree(node.getChild(0), rule_names)

        elif rule_name in [
            "expressionStatement",
            "expression",
            "loopExpression",
            "ifExpression",
        ]:
            return trim_expr(node, rule_names)

        elif rule_name == "letStatement":
            assert (
                node.getChildCount() == 5 or node.getChildCount() == 7
            ), "Assertion: Let statement must have 5 or 7 children"

            lhs_node = node.getChild(1).getChild(0).getChild(0)
            if isinstance(lhs_node.getChild(0), TerminalNode):
                is_mut = True
                nam = lhs_node.getChild(1).getChild(0).getSymbol().text
            else:
                is_mut = False
                nam = lhs_node.getChild(0).getChild(0).getSymbol().text

            offset = 0
            type_name = None
            if node.getChildCount() == 7:
                offset = 2
                type_name = trim_type(node.getChild(3), rule_names)

            rhs_node = trim_tree(node.getChild(offset + 3), rule_names)
            return {
                "assign": {
                    "is_mut": is_mut,
                    "type_name": type_name,
                    "nam": nam,
                    "val": rhs_node,
                }
            }
        elif rule_name == "macroInvocationSemi":
            raise NotImplementedError("Won't implement or macro statements")

        elif rule_name in ["item", "visItem"]:
            assert (
                node.getChildCount() == 1
            ), "Assertion: :item and :visItem must have ONLY 1 child"
            return trim_tree(node.getChild(0), rule_names)

        elif rule_name == "crate":
            all = []
            for i in range(node.getChildCount()):
                stmt = trim_tree(node.getChild(i), rule_names)
                if stmt != "":
                    all.append(stmt)

            # NOTE: blocks and statements are used as proxies for items
            return {"blk": {"body": {"seq": {"stmts": all}}}}
        else:
            raise NotImplementedError(f"Rule name {rule_name} not implemented in parse")

    return ""


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Parse a Rust file and output JSON")
    parser.add_argument("-i", "--input", type=str, required=True, help="Filepath of the Rust file to be parsed")
    parser.add_argument("-o", "--output", type=str, required=True, help="Filepath for the output JSON file")
    args = parser.parse_args()

    syntax_tree = parse_file(args.input)
    if syntax_tree:
        # Use the provided output path
        with open(args.output, "w", encoding="utf-8") as f:
            # print(syntax_tree)
            json.dump(syntax_tree, f, indent=2)
    else:
        print(f"ERROR response is not created {syntax_tree}")


#
#
# NOTE: FOOTNOTE
# - Operator precendence We don't impl
# ---- We don't do it, cause the antlr parse tree is left to right recursive
# ---- Also source doesn't do it either
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
