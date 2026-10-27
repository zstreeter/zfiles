"""python3 -m zdraft -- the draft module for bash callers.

  field FILE KEY     print a front-matter field; exit 1 if absent, 2 if no front matter
  vault PATH         print the vault holding PATH; exit 1 if none
  citekeys FILE...   print every citekey used, unique, sorted
  selftest
"""
import sys

from . import _selftest, citekeys, frontmatter, vault_of


def main(argv: list[str]) -> int:
    cmd, args = (argv[0], argv[1:]) if argv else ("", [])
    if cmd == "field" and len(args) == 2:
        fields, start = frontmatter(open(args[0], encoding="utf-8").read())
        if not start:
            return 2
        if args[1] not in fields:
            return 1
        print(fields[args[1]])
        return 0
    if cmd == "vault" and len(args) == 1:
        v = vault_of(args[0])
        if v is None:
            return 1
        print(v)
        return 0
    if cmd == "citekeys" and args:
        keys = set()
        for f in args:
            keys.update(k for _, k in citekeys(open(f, encoding="utf-8").read()))
        print("\n".join(sorted(keys)), end="\n" if keys else "")
        return 0
    if cmd == "selftest" and not args:
        _selftest()
        return 0
    print(__doc__.strip(), file=sys.stderr)
    return 2


sys.exit(main(sys.argv[1:]))
