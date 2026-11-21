## PythonSyntaxSpec holds PythonSyntax to Python as its header says it reads:
## comments, strings with every prefix, f-strings' fields, numbers, keywords
## hard and soft, decorators, types and names, each with the near misses that
## must stay plain. The tests live here, outside the lexer, so the lexer's
## module stays small.
import PythonSyntax
import Span

PythonSyntaxSpec :: [].{}

## The runs of `text` that get a color, each with its class and its text: what
## the expects below read.
colored_spans : Str -> List((Span.Class, Str))
colored_spans = |text| {
	bytes = text.to_utf8()
	PythonSyntax.spans(text)
		.keep_if(|span| span.class != Plain)
		.map(
			|span| (
				span.class,
				Str.from_utf8(
					bytes.sublist({ start: span.start, len: span.end - span.start }),
				) ?? crash "PythonSyntaxSpec.colored_spans: a span cuts a character",
			),
		)
}

## The colored runs of the lines, a newline after each but the last.
colored_lines : List(Str) -> List((Span.Class, Str))
colored_lines = |lines| colored_spans(Str.join_with(lines, "\n"))

## The words of the pieces, each piece a run of words apart by spaces.
words_of : List(Str) -> List(Str)
words_of = |pieces| pieces.join_map(|piece| piece.split_on(" "))

expect PythonSyntax.spans("") == []

# Comments run to their line's end, a quote or a brace in one included.
expect colored_lines(["x = 1  # a 'b' {c}", "# d"]) == [
	(Number, "1"),
	(Comment, "# a 'b' {c}"),
	(Comment, "# d"),
]

# Strings with both quotes, escapes, a line a backslash continues, and one
# still open, which stops at its line's end.
expect colored_spans("f(\"a\\\"b\", 'c\\'d', 'e\\\nf', \"\\N{BULLET}\")") == [
	(String, "\"a\\\"b\""),
	(String, "'c\\'d'"),
	(String, "'e\\\nf'"),
	(String, "\"\\N{BULLET}\""),
]
expect colored_lines(["x = 'ab", "y = 1"]) == [(String, "'ab"), (Number, "1")]

# Triple-quoted strings span lines and hold single quotes; one never closed
# runs to the end.
expect colored_lines(["'''a 'b'", "\"\"c\"\"\"'''x", "\"\"\"d\\\"\"\" e\"\"\""]) == [
	(String, "'''a 'b'\n\"\"c\"\"\"'''"),
	(String, "\"\"\"d\\\"\"\" e\"\"\""),
]
expect colored_spans("x = \"\"\"a\nb") == [(String, "\"\"\"a\nb")]
expect colored_spans("'' \"\" ''''''") == [
	(String, "''"),
	(String, "\"\""),
	(String, "''''''"),
]

# Every prefix in either case; a raw string's backslash still keeps a quote
# in it; a word that isn't a prefix is a name before its string.
expect
	words_of([
		"r'a' R'a' b'a' B'a' u'a' U'a' br'a' Br'a' bR'a' BR'a'",
		"rb'a' rB'a' Rb'a' RB'a' rb'''a'''",
	])
		.all(|word| colored_spans(word) == [(String, word)])
expect colored_spans("r'\\'' r\"\\\\\" ur'x' bu'y'") == [
	(String, "r'\\''"),
	(String, "r\"\\\\\""),
	(String, "'x'"),
	(String, "'y'"),
]

# An f-string's fields are code: the text between them is a string, and the
# braces plain. `{{` and `}}` are text.
expect colored_spans("f'a {b + 1} c {{d}}'") == [
	(String, "f'a "),
	(Number, "1"),
	(String, " c {{d}}'"),
]
expect colored_spans("F\"{x}\" fr'{y}\\d' Rf'\\{z}' t'{w}' TR'{v}'") == [
	(String, "F\""),
	(String, "\""),
	(String, "fr'"),
	(String, "\\d'"),
	(String, "Rf'\\"),
	(String, "'"),
	(String, "t'"),
	(String, "'"),
	(String, "TR'"),
	(String, "'"),
]

# Python 3.12's fields: the f-string's own quote inside, nested f-strings,
# keywords and comments, and a field spanning lines in a one-quote f-string.
expect colored_spans("f\"{d[\"k\"]} {f\"{1 if a else 2}\"}\"") == [
	(String, "f\""),
	(String, "\"k\""),
	(String, " "),
	(String, "f\""),
	(Number, "1"),
	(Keyword, "if"),
	(Keyword, "else"),
	(Number, "2"),
	(String, "\""),
	(String, "\""),
]
expect colored_lines(["f\"{', '.join([", "    'a',  # one '}'", "])}\""]) == [
	(String, "f\""),
	(String, "', '"),
	(String, "'a'"),
	(Comment, "# one '}'"),
	(String, "\""),
]

# Format specs are text with nested fields; a conversion and `=` are code.
expect colored_spans("f'{x:>{width}.{p}f} {y!r:^10} {z=} {w:%H:%M}'") == [
	(String, "f'"),
	(String, ">"),
	(String, "."),
	(String, "f"),
	(String, " "),
	(String, "^10"),
	(String, " "),
	(String, " "),
	(String, "%H:%M"),
	(String, "'"),
]
expect colored_spans("f'{a[1:2]} {b:{c}}'") == [
	(String, "f'"),
	(Number, "1"),
	(Number, "2"),
	(String, " "),
	(String, "'"),
]

# A triple-quoted f-string spans lines; a one-quote f-string still open stops
# at its line's end, and so does its open format spec.
expect colored_lines(["f'''a", "{b}", "c'''"]) == [(String, "f'''a\n"), (String, "\nc'''")]
expect colored_lines(["f'a {b}", "c = 1"]) == [(String, "f'a "), (Number, "1")]
expect colored_lines(["f'{a:b", "c = 1"]) == [
	(String, "f'"),
	(String, "b"),
	(Number, "1"),
]
expect colored_spans("f'{a") == [(String, "f'")]
expect colored_spans("f'\\N{DASH} {x}' rf'\\N{x}'") == [
	(String, "f'\\N{DASH} "),
	(String, "'"),
	(String, "rf'\\N"),
	(String, "'"),
]

# Numbers in every base, with separators, fractions, exponents and `j`.
expect
	colored_lines([
		"f(0, 10, 1_000, 0x1F, 0X_ff, 0o17, 0b1010,",
		"  1.5, .5, 1., 1e10, 2.5E-3, 1_0.0_1e+1_0, 3j, 1.5J, 1e3j)",
	])
		== [
			(Number, "0"),
			(Number, "10"),
			(Number, "1_000"),
			(Number, "0x1F"),
			(Number, "0X_ff"),
			(Number, "0o17"),
			(Number, "0b1010"),
			(Number, "1.5"),
			(Number, ".5"),
			(Number, "1."),
			(Number, "1e10"),
			(Number, "2.5E-3"),
			(Number, "1_0.0_1e+1_0"),
			(Number, "3j"),
			(Number, "1.5J"),
			(Number, "1e3j"),
		]
expect colored_spans("a1 x.b2 a[1:-2] 1e x...") == [
	(Number, "1"),
	(Number, "2"),
	(Number, "1"),
]

# Every hard keyword, each its own span, and words that hold one.
expect
	words_of([
		"False None True and as assert async await break class continue def",
		"del elif else except finally for from global if import in is lambda",
		"nonlocal not or pass raise return try while with yield",
	]).all(|word| colored_spans(word) == [(Keyword, word)])
expect colored_spans("iffy none true _if Return self print") == []

# The name `def` or `class` declares; a call is plain.
expect colored_spans("async def f(x): return f(x)") == [
	(Keyword, "async"),
	(Keyword, "def"),
	(Name, "f"),
	(Keyword, "return"),
]
expect colored_spans("class Box(Base): pass") == [
	(Keyword, "class"),
	(Name, "Box"),
	(Keyword, "pass"),
]

# The built-in types, but not after a `.`; a relative import's `.` before a
# keyword leaves it a keyword.
expect
	words_of([
		"bool bytearray bytes complex dict float frozenset int list",
		"memoryview object range set slice str tuple type",
	])
		.all(|word| colored_spans(word) == [(Type, word)])
expect colored_spans("np.int x.type from . import y") == [(Keyword, "from"), (Keyword, "import")]

# Decorators, first in their statement, with a dotted name; `@` elsewhere is
# matrix multiplication.
expect colored_lines([
	"@property",
	"  @functools.lru_cache(maxsize=None)",
	"def f(): return a @ b",
	"x = (a",
	"     @ b)",
]) == [
	(Name, "@property"),
	(Name, "@functools.lru_cache"),
	(Keyword, "None"),
	(Keyword, "def"),
	(Name, "f"),
	(Keyword, "return"),
]

# The soft keywords where their statements start, and the same words as
# names everywhere else.
expect colored_lines([
	"match command.split():",
	"    case [\"go\", direction] if direction:",
	"        pass",
	"    case (1 |",
	"          2) | _:",
	"    case _:",
	"        type Point = tuple[float, float]",
	"lazy import json",
]) == [
	(Keyword, "match"),
	(Keyword, "case"),
	(String, "\"go\""),
	(Keyword, "if"),
	(Keyword, "pass"),
	(Keyword, "case"),
	(Number, "1"),
	(Number, "2"),
	(Keyword, "_"),
	(Keyword, "case"),
	(Keyword, "_"),
	(Keyword, "type"),
	(Name, "Point"),
	(Type, "tuple"),
	(Type, "float"),
	(Type, "float"),
	(Keyword, "lazy"),
	(Keyword, "import"),
]
expect colored_lines([
	"match = re.match(p, s)",
	"match(x)",
	"case.lower(); type(x) == int",
	"print(match, case, _); type = 3",
	"lazy = 1; _ = 2",
	"type X[T] = list[T]",
]) == [
	(Type, "type"),
	(Type, "int"),
	(Type, "type"),
	(Number, "3"),
	(Number, "1"),
	(Number, "2"),
	(Keyword, "type"),
	(Name, "X"),
	(Type, "list"),
]

# A statement starts after a `;`, and not on a line a backslash joins on or
# inside brackets.
expect colored_lines([
	"x = 1; match y:",
	"z = \\",
	"  @a",
	"f(",
	"  @b)",
]) == [(Number, "1"), (Keyword, "match")]
expect colored_spans("+ - * / // % ** := -> << >> & | ^ ~ < > <= >= == != , : ; ! ? $ ` é") == []
