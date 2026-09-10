"""Portability rules for every Maya-side file. No Maya needed.

Windows Python defaults to cp1252 for files and consoles, and it has no ▸, →, ⚠ …
One stray character in a string that gets written or printed is enough to crash — and it
once truncated a user's userSetup.py. So:
  1. string literals (other than docstrings) are pure ASCII
  2. every open() names an encoding or is binary
"""
import ast
import glob
import os
import unittest

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
FILES = sorted(glob.glob(os.path.join(ROOT, "driving_rig", "*.py")) + [os.path.join(ROOT, "install_driving_rig.py")])


def _docstring_ids(tree):
    ids = set()
    for node in ast.walk(tree):
        if isinstance(node, (ast.Module, ast.ClassDef, ast.FunctionDef, ast.AsyncFunctionDef)) and node.body:
            first = node.body[0]
            if isinstance(first, ast.Expr) and isinstance(first.value, ast.Constant):
                ids.add(id(first.value))
    return ids


class Hygiene(unittest.TestCase):
    def test_files_found(self):
        self.assertGreaterEqual(len(FILES), 9)

    def test_string_literals_are_ascii(self):
        bad = []
        for f in FILES:
            with open(f, encoding="utf-8") as fh:
                tree = ast.parse(fh.read())
            docs = _docstring_ids(tree)
            for n in ast.walk(tree):
                if isinstance(n, ast.Constant) and isinstance(n.value, str) and id(n) not in docs \
                        and not n.value.isascii():
                    bad.append("%s:%d %r" % (os.path.basename(f), n.lineno, n.value[:40]))
        self.assertEqual(bad, [], "non-ASCII string literals (crash on Windows cp1252):\n" + "\n".join(bad))

    def test_open_is_explicit(self):
        bad = []
        for f in FILES:
            with open(f, encoding="utf-8") as fh:
                tree = ast.parse(fh.read())
            for n in ast.walk(tree):
                if isinstance(n, ast.Call) and getattr(n.func, "id", None) == "open":
                    mode = n.args[1].value if len(n.args) > 1 and isinstance(n.args[1], ast.Constant) else ""
                    mode = next((k.value.value for k in n.keywords if k.arg == "mode"), mode)
                    if "b" not in mode and "encoding" not in {k.arg for k in n.keywords}:
                        bad.append("%s:%d" % (os.path.basename(f), n.lineno))
        self.assertEqual(bad, [], "open() without encoding= (locale-dependent):\n" + "\n".join(bad))


if __name__ == "__main__":
    unittest.main()
