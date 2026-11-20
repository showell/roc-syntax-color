# roc-syntax-color

A Roc package that colors source code for web pages: code text in, HTML out,
with a `<span class="syn-...">` around each comment, string, number, keyword,
name and type. It colors four languages: Roc, Shale, JavaScript and Zig. It is
pure functions from bytes to bytes, with no dependencies and no platform, so
any Roc app can import it, and no text makes it fail: an unterminated string or
half a program still comes out with every byte covered.

The class names are `syn-comment`, `syn-string`, `syn-number`, `syn-keyword`,
`syn-name` and `syn-type`; your stylesheet gives them their colors.

## Using it from a Roc app

Check this repository out beside your app's and name the package by relative
path, as roc-chat names roc-markdown:

```roc
app [main!] {
	pf: platform "...",
	sc: "../../roc-syntax-color/package/main.roc",
}

import sc.SyntaxColor

page_code : Str -> Str
page_code = |code| "<pre><code>${SyntaxColor.html(SyntaxColor.roc, code)}</code></pre>"
```

The path is relative to the file that names it. Build with the Roc that
`roc-version` pins (a nightly's tag): Roc's packages change between nightlies.

## The interface

`package/SyntaxColor.roc` is the interface:

- `SyntaxColor.html(language, text)` is the whole text, colored and escaped.
- `SyntaxColor.spans(language, text)` is the lexer's answer: a list of `Span`s,
  `{ class, start, end }` over the text's bytes, covering every byte once, in
  order. `class` is `Plain`, `Comment`, `String`, `Number`, `Keyword`, `Name` or
  `Type` (`package/Span.roc`).
- `SyntaxColor.range_html(text, { spans, start, end })` is a byte range of the
  text, colored by the spans of the whole. A page that shows part of a file
  colors the file once and takes the ranges it shows, so a block cut from a
  function's body is colored as it reads there.
- `SyntaxColor.escaped_text(text)` is the text with `&`, `<`, `>`, `"` and `'`
  escaped, as both the spans and the text between them are.

A language is a `SyntaxColor.Language`, `{ name, spans }`, whose `spans` is its
lexer. `SyntaxColor.roc`, `SyntaxColor.shale`, `SyntaxColor.js` and
`SyntaxColor.zig` are the four there are, each lexer a module of its own.
Another language is one more module with a `spans : Str -> List(Span)` and one
more value beside those.

## Checking it

    shale tools/verify.shale

runs `roc fmt --check`, `roc check`, `roc test` and an oracle of real samples,
each colored byte for byte as recorded. [DESIGN.md](DESIGN.md) says how the
lexers read each language, what the oracle holds and where it stands.

It began in [roc-apps](https://github.com/showell/roc-apps), where the Safari
tutorial and the books book color their code with it; its history came with
it.

## License

The Universal Permissive License, version 1.0 ([LICENSE](LICENSE)).
