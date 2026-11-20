# roc-syntax-color

A Roc package that colors Roc, Shale, JavaScript and Zig for web pages
([README.md](README.md); how the lexers and the oracle work is
[DESIGN.md](DESIGN.md)).

The general habits are roc-apps' (its `CLAUDE.md` and `docs/roc-style.md`):
the Roc quality standard, the commit and gate rules, Shale for every shell
step. This file adds only what is particular here.

- **The gate** is `shale tools/verify.shale`, from the root. A change is done
  when it prints `verify: N of N passed`. Its counts (`EXPECTS`, `CORPORA`,
  `ALONE_MATCHES`) are held exact: move one only with the change that moves
  it, and say why in the commit. So are the Roc recipes' counts, in
  `tools/lints.shale`'s `HELD`, which came from roc-apps' quality baseline.
- **The Roc is the pin** in `roc-version`, at `tools:roc-<pin>/roc`. It moves
  with roc-apps' pin, since roc-apps and roc-chat import this package.
- **The oracle is recorded, not edited.** The `tools/record_*.shale` scripts
  run from a roc-apps checkout with this one beside it, since the samples are
  other repositories' files. Re-record only for a deliberate change, and read
  the diff.
- **Users name the package by relative path**, from a checkout beside theirs:
  roc-apps (the Safari tutorial and the books book) and roc-chat. A change to
  the interface is a change to them.
- The repository is public: no hosts, addresses or accounts in it.
