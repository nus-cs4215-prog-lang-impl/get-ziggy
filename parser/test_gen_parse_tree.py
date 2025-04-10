import unittest
import gen_parse_tree as parser
import json

prefix = "./test_examples"


class TestParseBasics(unittest.TestCase):

    def test_path_expr(self):
        out = parser.parse_file(f"{prefix}/path_expr.rs")
        with open(f"{prefix}/path_expr.json", "r") as f:
            golden_example = json.load(f)
        self.assertEqual(out, golden_example)

    def test_functions(self):
        out = parser.parse_file(f"{prefix}/functions.rs")
        with open(f"{prefix}/functions.json", "r") as f:
            golden_example = json.load(f)
        self.assertEqual(out, golden_example)

    def test_infix(self):
        out = parser.parse_file(f"{prefix}/infix.rs")
        with open(f"{prefix}/infix.json", "r") as f:
            golden_example = json.load(f)
        self.assertEqual(out, golden_example)

    def test_prefix(self):
        out = parser.parse_file(f"{prefix}/prefix.rs")
        with open(f"{prefix}/prefix.json", "r") as f:
            golden_example = json.load(f)
        self.assertEqual(out, golden_example)

    def test_postfix(self):
        out = parser.parse_file(f"{prefix}/postfix.rs")
        with open(f"{prefix}/postfix.json", "r") as f:
            golden_example = json.load(f)
        self.assertEqual(out, golden_example)

    def test_literals_expr(self):
        out = parser.parse_file(f"{prefix}/literals.rs")
        with open(f"{prefix}/literals.json", "r") as f:
            golden_example = json.load(f)
        self.assertEqual(out, golden_example)

    def test_blk_expr(self):
        out = parser.parse_file(f"{prefix}/block_expr.rs")
        with open(f"{prefix}/block_expr.json", "r") as f:
            golden_example = json.load(f)
        self.assertEqual(out, golden_example)

    def test_let_stmt(self):
        out = parser.parse_file(f"{prefix}/let_stmt.rs")
        with open(f"{prefix}/let_stmt.json", "r") as f:
            golden_example = json.load(f)
        self.assertEqual(out, golden_example)

    def test_if_expr(self):
        out = parser.parse_file(f"{prefix}/if_expr.rs")
        with open(f"{prefix}/if_expr.json", "r") as f:
            golden_example = json.load(f)
        self.assertEqual(out, golden_example)

    def test_loop_expr(self):
        out = parser.parse_file(f"{prefix}/loop_expr.rs")
        with open(f"{prefix}/loop_expr.json", "r") as f:
            golden_example = json.load(f)
        self.assertEqual(out, golden_example)

    def test_rtn_brk_cont(self):
        out = parser.parse_file(f"{prefix}/rtn_brk_cont.rs")
        with open(f"{prefix}/rtn_brk_cont.json", "r") as f:
            golden_example = json.load(f)
        self.assertEqual(out, golden_example)

    def test_everything_burger(self):
        out = parser.parse_file(f"{prefix}/everything_burger.rs")
        with open(f"{prefix}/everything_burger.json", "r") as f:
            golden_example = json.load(f)
        self.assertEqual(out, golden_example)


if __name__ == "__main__":
    unittest.main()
