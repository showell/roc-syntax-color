# roc-syntax-color

A Roc package that colors source code for web pages. Code goes in and HTML comes out, with a `<span class="syn-...">` around each comment, string, number, keyword, name and type. It colors four languages: Roc, JavaScript, Zig and [Shale](https://github.com/showell/shale), a small scripting language used to build this repo and its siblings.

It's pure functions from bytes to bytes, with no dependencies and no platform, so any Roc app can import it. No input makes it fail: an unterminated string or half a program still comes out colored, with every byte accounted for.

## An example

```roc
SyntaxColor.html(SyntaxColor.roc, "x = 1 # one")
```

gives

```html
<span class="syn-name">x</span> = <span class="syn-number">1</span> <span class="syn-comment"># one</span>
```

Your stylesheet picks the colors. The six classes are `syn-comment`, `syn-string`, `syn-number`, `syn-keyword`, `syn-name` and `syn-type`, for example:

```css
.syn-comment { color: #6a737d; }
.syn-keyword { color: #d73a49; }
.syn-string  { color: #032f62; }
```

## Using it from a Roc app

Clone this repository beside your app's and name the package by its relative path:

```roc
app [main!] {
	pf: platform "...",
	sc: "../roc-syntax-color/package/main.roc",
}

import sc.SyntaxColor

page_code : Str -> Str
page_code = |code| "<pre><code>${SyntaxColor.html(SyntaxColor.roc, code)}</code></pre>"
```

The path is relative to the file that names it. Build with the Roc nightly that `roc-version` names, because Roc's packages change between nightlies.

## The interface

It all lives in `package/SyntaxColor.roc`:

- `SyntaxColor.html(language, text)` is the whole text, colored and HTML-escaped.
- `SyntaxColor.spans(language, text)` is the raw answer: a list of spans, each `{ class, start, end }` over the text's bytes, covering every byte exactly once, in order. A span's `class` is `Plain`, `Comment`, `String`, `Number`, `Keyword`, `Name` or `Type`.
- `SyntaxColor.range_html(text, { spans, start, end })` colors one byte range of the text using the spans of the whole. Color a file once, then show any part of it colored as it reads in place.
- `SyntaxColor.escaped_text(text)` is the text with `&`, `<`, `>`, `"` and `'` escaped, the same escaping the colored output uses.

The languages are `SyntaxColor.roc`, `SyntaxColor.js`, `SyntaxColor.zig` and `SyntaxColor.shale`. Each one is a module with its own lexer. Adding a language means one more module with a `spans : Str -> List(Span)` function, plus one more value beside those four.

## Checking it

The tests are ordinary Roc `expect`s, so `roc test package/main.roc` runs them. The full check also runs `roc fmt --check`, `roc check`, some style checks, and a set of real files from other projects whose expected coloring is recorded byte for byte. That full check is a Shale script:

    shale tools/verify.shale

[DESIGN.md](DESIGN.md) explains how each lexer reads its language and how the recorded samples are kept.

## Where it's used

It started inside [roc-apps](https://github.com/showell/roc-apps), where it colors the code in a Roc tutorial book. It moved here, with its history, so that other apps could use it too. [roc-chat](https://github.com/showell/roc-chat), a chat server written in Roc, is adding it to color code blocks in messages.

## License

The Universal Permissive License, version 1.0 ([LICENSE](LICENSE)).
