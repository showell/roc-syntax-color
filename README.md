# roc-syntax-color

A Roc package that colors source code for web pages. Code goes in and HTML comes out, with a `<span class="syn-...">` around each comment, string, number, keyword, name and type. It colors four languages: Roc, JavaScript, Zig and [Shale](https://github.com/showell/shale), a small scripting language by the same author. Using the package takes only Roc.

The code was written by Claude, an AI coding agent, working from its author's direction, and the repository is set up for agents to keep extending it: point one at this repo and ask for a new language, and the steps below are what it follows.

It's pure functions from `Str` to `Str` that stand alone, so any Roc app on any platform can import it. Any text at all can be colored: an unterminated string or half a program still comes out colored, and the HTML with its tags removed is exactly the escaped input.

## An example

```roc
SyntaxColor.html(SyntaxColor.roc, "x = 1 # one")
```

gives

```html
<span class="syn-name">x</span> = <span class="syn-number">1</span> <span class="syn-comment"># one</span>
```

Your stylesheet picks the colors. The six classes are `syn-comment`, `syn-string`, `syn-number`, `syn-keyword`, `syn-name` and `syn-type`. Everything else (operators, punctuation, spaces) is plain text. For example:

```css
.syn-comment { color: #6a737d; }
.syn-keyword { color: #d73a49; }
.syn-string  { color: #032f62; }
```

## Using it from a Roc app

To use it, clone this repository next to your app's repository and name the package by its relative path:

```roc
app [main!] {
	pf: platform "...",
	sc: "../roc-syntax-color/package/main.roc",
}

import sc.SyntaxColor

page_code : Str -> Str
page_code = |code| "<pre><code>${SyntaxColor.html(SyntaxColor.roc, code)}</code></pre>"
```

The path is relative to the file that names it. The file `roc-version` names the Roc nightly this package is tested with. Use that one, since Roc changes between nightlies.

## The interface

It all lives in `package/SyntaxColor.roc`:

- `SyntaxColor.html(language, text)` is the whole text, colored and HTML-escaped.
- `SyntaxColor.spans(language, text)` is the raw answer: a list of spans, each `{ class, start, end }` over the text's bytes, covering every byte exactly once, in order. A span's `class` is `Plain`, `Comment`, `String`, `Number`, `Keyword`, `Name` or `Type`.
- `SyntaxColor.range_html(text, { spans, start, end })` colors one byte range of the text using the spans of the whole. Color a file once, then show any part of it colored as it reads in place. The range must start and end on character boundaries; one that ends inside a UTF-8 character stops the program.
- `SyntaxColor.escaped_text(text)` is the text with `&`, `<`, `>`, `"` and `'` escaped, the same escaping the colored output uses.

A language is a `SyntaxColor.Language`, a record `{ name, spans }` whose `spans : Str -> List(Span)` is its lexer. The four are `SyntaxColor.roc`, `SyntaxColor.js`, `SyntaxColor.zig` and `SyntaxColor.shale`, named `"roc"`, `"js"`, `"zig"` and `"shale"`. Each lexer is a module of its own: `RocSyntax.roc`, `JsSyntax.roc` and so on.

## Adding a language

1. Write `package/FooSyntax.roc` with a `spans` function that covers every byte exactly once.
2. Add it to the `package [...]` list in `package/main.roc`.
3. Add a `foo` value beside the four in `SyntaxColor.roc`, with an `expect` that holds it to the hostile texts there.
4. Record some real files as samples in `oracle/` ([DESIGN.md](DESIGN.md) says how).

The full check holds its counts exactly, so the same change updates them.

## Checking it

`roc test package/main.roc` runs the tests with Roc alone. The full check, which contributors run before a pull request, also runs:
- `roc fmt --check` and `roc check`;
- the repository's style checks;
- real files whose coloring is recorded byte for byte in `oracle/`. For Roc and Shale, those samples match the colorers this package replaced. For JavaScript and Zig, they're the package's own answers, read by eye, so they guard against changes.

The full check is a Shale script, so it needs [Shale](https://github.com/showell/shale) installed:

    shale tools/verify.shale

[DESIGN.md](DESIGN.md) explains how each lexer reads its language and how the samples are kept.

## Where it's used

It colors the code in two books in [roc-apps](https://github.com/showell/roc-apps), where it started, and it moved here with its history so other apps could use it.

## License

The Universal Permissive License, version 1.0 ([LICENSE](LICENSE)).
