# How roc-syntax-color works

The lexers, the gate that holds them to an oracle, and where they stand.
[README.md](README.md) has the interface.

## Lexical, with brackets

The lexers read bytes, not a tree. JavaScript's keeps a stack of braces, for
a template's `${...}`, and the token before, to tell a regular expression's
`/` from division's. Zig's follows Zig's own tokenizer
(lib/std/zig/tokenizer.zig in Zig's standard library), keeping only whether
the token before was `fn` or a `.`: the name after `fn` is a name, and a word
after a `.` is a field, never a keyword or a type. Its primitive types (`u8`,
`usize`, `type`, `anytype`) are types, and its builtins (`@import`) are
keywords. Shale's follows Shale's own lexer (`src/script/lex.zig` in the
shale repository). Roc's has no lexer of record to
follow, and its samples were first recorded from a colorer that read roc-ast's
tree, so RocSyntax keeps the little it needs to agree with the tree: which brackets are open and what the token
before was. That tells a top-level definition's name from a local's, and a
function's body from a record. `RocSyntax.roc`'s header says the rules.

## The gate and the oracle

    shale tools/verify.shale

It runs `roc fmt --check`, `roc check` and `roc test` (its count held exact),
builds `harness/main.roc` on Roc's echo platform, and holds the harness's
answer for every sample in `oracle/` to what was recorded, byte for byte. A
sample known to differ is named in `oracle/known_mismatches.txt` with its
reason, and the list is held exact both ways.

The Roc, JavaScript and Zig samples are the package's own answers, frozen:
re-record them only after a deliberate change to a lexer, and read every
sample that moved in the diff. `tools/record_roc_fixtures.shale` colors the
Roc samples' frozen texts again, from this checkout;
`tools/record_js_fixtures.shale` and `tools/record_zig_fixtures.shale` read
their files from a roc-apps checkout with this one beside it. The Shale
samples are what the Shale cookbook's `color_shale.shale` makes of them, and
`tools/record_shale_oracle.shale` records them again, from a roc-apps checkout
with this repository, the books book's checkout and the Shale cookbook beside
it. Each recorder's header says what it writes.

A header's keywords follow Roc's tokenizer at the pin: `app`, `hosted`,
`module`, `package` and `platform` start one, and in it those words and a
platform header's sections, `requires`, `exposes`, `packages`, `provides`,
`hosted` and `targets`, are keywords. The header runs to the next line that
starts at its first column.

## Where the samples came from

The Roc samples are every Roc block of the Safari book (223) and every file
those blocks quote (76). They were first recorded from roc-apps'
`color_roc.shale`, the colorer this package replaced, which read roc-ast's
tree. The package matches those recordings byte for byte except in seven
samples, where it colors what color_roc left plain: web.roc's app header,
whole and in one block, whose spans roc-ast gave overlapping, and a qualified
type in a lambda's unwrap pattern, `|Route.SegmentIndex.(n)|`, in four files
and one block. On 2026-11-20 color_roc retired, and the samples were recorded
again as the package's own answers, read by eye; those seven are all that
moved.

## Status (2026-11-20)

- Colored alone, without their files, 219 of the 223 Roc blocks match how they
  read in their files. The other four are cut from a function's body, whose
  `name = ...` lines read as top-level definitions alone.
- 107 of 109 Shale samples match color_shale; the two others are fragments
  color_shale refuses because they fail `shale --check` alone.
- JavaScript had no colorer before, so its 13 fixtures (`oracle/js_files.jsonl`,
  from `tools/record_js_fixtures.shale`) are the package's own answers, read
  by eye.
- Zig had none either: its 13 fixtures (`oracle/zig_files.jsonl`, from
  `tools/record_zig_fixtures.shale`) are real files from Shale, the book
  builder's host, roc-chat's host, zig-webbox and zig-metal-unikernel, read by
  eye the same way.
- The gate takes about 3 seconds on a warm Roc cache.
- Two books in roc-apps color their code with it, behind the book builder's
  coloring hook: the Safari tutorial (`canvas_apps/safari/tutorial/app/QuotedColor.roc`)
  and the books book (`building-books/app/main.roc`).

## Pitfalls

- A record literal opened right after `=` reads as a body, so a `name : value`
  field in it, spaced as an annotation is, would count as a definition.
  `roc fmt` writes fields as `name: value`, which never does.
