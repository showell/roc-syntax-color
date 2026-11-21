## OdinSyntaxSpec holds OdinSyntax to Odin as its header says it reads:
## comments that nest, strings of every quoting, numbers in every base,
## directives, attributes, keywords, types and names, each with the near misses
## that must stay plain. The tests live here, outside the lexer, so the lexer's
## module stays small.
import OdinSyntax
import Span

OdinSyntaxSpec :: [].{}

## The runs of `text` that get a color, each with its class and its text: what
## the expects below read.
colored_spans : Str -> List((Span.Class, Str))
colored_spans = |text| {
	bytes = text.to_utf8()
	OdinSyntax.spans(text)
		.keep_if(|span| span.class != Plain)
		.map(
			|span| (
				span.class,
				Str.from_utf8(
					bytes.sublist({ start: span.start, len: span.end - span.start }),
				) ?? crash "OdinSyntaxSpec.colored_spans: a span cuts a character",
			),
		)
}

## The colored runs of the lines, a newline after each but the last.
colored_lines : List(Str) -> List((Span.Class, Str))
colored_lines = |lines| colored_spans(Str.join_with(lines, "\n"))

## The words of the pieces, each piece a run of words apart by spaces.
words_of : List(Str) -> List(Str)
words_of = |pieces| pieces.join_map(|piece| piece.split_on(" "))

expect OdinSyntax.spans("") == []

# Line comments, a shebang, and block comments, which nest: an inner `*/`
# closes only the inner one.
expect colored_lines(["#!/usr/bin/env odin", "a // b /* c", "x"]) == [
	(Comment, "#!/usr/bin/env odin"),
	(Comment, "// b /* c"),
]
expect colored_spans("/* a /* b */ c */ x /* d") == [
	(Comment, "/* a /* b */ c */"),
	(Comment, "/* d"),
]
expect colored_lines(["/* one", "  /* two /* three */", "  */ still", "*/ out"]) == [
	(Comment, "/* one\n  /* two /* three */\n  */ still\n*/"),
]

# The tokenizer's own reading of a `/*/` inside: it opens one and closes it.
# A `/*/` that opens a comment closes nothing.
expect colored_spans("/* /*/ */ x") == [(Comment, "/* /*/ */")]
expect colored_spans("/*/ x */ y") == [(Comment, "/*/ x */")]

# Quoted strings and runes with escapes; one still open stops at its line's
# end, a backslash before it included.
expect colored_spans("f(\"a\\\"b\\\\\", 'c', '\\'', '\\n', \"\\x41\\u00e9\")") == [
	(String, "\"a\\\"b\\\\\""),
	(String, "'c'"),
	(String, "'\\''"),
	(String, "'\\n'"),
	(String, "\"\\x41\\u00e9\""),
]
expect colored_spans("x := \"ab\ny := 'c\nz := \"d\\\n1") == [
	(String, "\"ab"),
	(String, "'c"),
	(String, "\"d\\"),
	(Number, "1"),
]

# A raw string runs across lines and keeps its backslashes, to its backtick or
# the text's end; three quotes, of either kind, run to the next three.
expect colored_spans("re := `a\\d+\n\"b\"` + `open") == [
	(String, "`a\\d+\n\"b\"`"),
	(String, "`open"),
]
expect colored_lines(["s := \"\"\"a \"\" b", "\\\"\"\"\" x"]) == [
	(String, "\"\"\"a \"\" b\n\\\"\"\"\""),
]
expect colored_spans("```a ` `` b\\``` `x") == [(String, "```a ` `` b\\```"), (String, "`x")]
expect colored_spans("\"\" `` x") == [(String, "\"\""), (String, "``")]

# Numbers in every base, with separators, fractions, exponents and the
# imaginary and quaternion suffixes.
expect
	colored_lines([
		"f(0, 10, 1_000, 017, 0b1010, 0o17, 0d99, 0z1ab, 0xFF_ff, 0h3C00,",
		"  1.5, .5, 1., 1e10, 1.5e-3, 2E+4, 2i, 1.5j, 3k, 0x1Fi)",
	])
		== [
			(Number, "0"),
			(Number, "10"),
			(Number, "1_000"),
			(Number, "017"),
			(Number, "0b1010"),
			(Number, "0o17"),
			(Number, "0d99"),
			(Number, "0z1ab"),
			(Number, "0xFF_ff"),
			(Number, "0h3C00"),
			(Number, "1.5"),
			(Number, ".5"),
			(Number, "1."),
			(Number, "1e10"),
			(Number, "1.5e-3"),
			(Number, "2E+4"),
			(Number, "2i"),
			(Number, "1.5j"),
			(Number, "3k"),
			(Number, "0x1Fi"),
		]

# A number stops where its digits do, before a range, and before a letter its
# base doesn't take.
expect colored_spans("0..<10 1..=n a[1:] 9abc 0b12 1.5.x 1e+ 0x") == [
	(Number, "0"),
	(Number, "10"),
	(Number, "1"),
	(Number, "1"),
	(Number, "9"),
	(Number, "0b12"),
	(Number, "1.5"),
	(Number, "1e+"),
	(Number, "0x"),
]

# Directives and a file's tag are keywords: the tag runs to its line's end or
# a comment, a directive is its word alone, and a `#` alone is plain.
expect colored_lines([
	"#+build linux, darwin // a",
	"#+private",
	"#partial switch k { }",
	"x := #load(\"a.txt\") # y",
	"#assert(size_of(T) == 8)",
]) == [
	(Keyword, "#+build linux, darwin "),
	(Comment, "// a"),
	(Keyword, "#+private"),
	(Keyword, "#partial"),
	(Keyword, "switch"),
	(Keyword, "#load"),
	(String, "\"a.txt\""),
	(Keyword, "#assert"),
	(Number, "8"),
]

# An attribute's `@` and the attributes its list names are keywords; a value
# after `=` is a value. `@name` alone is one keyword.
expect colored_lines([
	"@(private=\"file\", require_results)",
	"@(link_name=puts, linkage=\"strong\") foo :: proc() ---",
	"@require_results bar :: proc(x: int) -> int { return x }",
]) == [
	(Keyword, "@"),
	(Keyword, "private"),
	(String, "\"file\""),
	(Keyword, "require_results"),
	(Keyword, "@"),
	(Keyword, "link_name"),
	(Keyword, "linkage"),
	(String, "\"strong\""),
	(Name, "foo"),
	(Keyword, "proc"),
	(Keyword, "---"),
	(Keyword, "@require_results"),
	(Name, "bar"),
	(Keyword, "proc"),
	(Type, "int"),
	(Type, "int"),
	(Keyword, "return"),
]
expect colored_spans("@(a=(b), c) d") == [
	(Keyword, "@"),
	(Keyword, "a"),
	(Keyword, "c"),
]

# A name right before `::` is declared; `:=` and a plain `:` declare nothing.
expect colored_lines([
	"Vec :: struct($T: typeid) { x, y: T }",
	"N  :: 4",
	"main :: proc() { v := Vec(f32){}; w: int }",
]) == [
	(Name, "Vec"),
	(Keyword, "struct"),
	(Type, "$T"),
	(Type, "typeid"),
	(Name, "N"),
	(Number, "4"),
	(Name, "main"),
	(Keyword, "proc"),
	(Type, "f32"),
	(Type, "int"),
]

# Every keyword, each its own span, and words that hold one or follow a dot.
expect
	words_of([
		"asm auto_cast bit_field bit_set break case cast context continue defer",
		"distinct do dynamic else enum fallthrough false for foreign if import in",
		"map matrix nil not_in or_break or_continue or_else or_return package proc",
		"return struct switch transmute true union using when where",
	]).all(|word| colored_spans(word) == [(Keyword, word)])
expect colored_lines(["iffy procs _if Return NIL foreach", "x.proc .Enum context.allocator"]) == [
	(Keyword, "context"),
]

# The built-in types, endian ones too, and near misses.
expect
	words_of([
		"any b8 b16 b32 b64 bool byte complex32 complex64 complex128 cstring",
		"cstring16 f16 f16be f16le f32 f32be f32le f64 f64be f64le i8 i16 i16be",
		"i16le i32 i32be i32le i64 i64be i64le i128 i128be i128le int",
		"quaternion64 quaternion128 quaternion256 rawptr rune string string16",
		"typeid u8 u16 u16be u16le u32 u32be u32le u64 u64be u64le u128 u128be",
		"u128le uint uintptr",
	]).all(|word| colored_spans(word) == [(Type, word)])
expect colored_spans("u7 i256 f8 Int strings x.int $ $1 ^u8 []rune") == [
	(Number, "1"),
	(Type, "u8"),
	(Type, "rune"),
]

# `---` is a keyword, as the tokenizer reads three dashes; `--` is plain.
expect colored_spans("x: [4]int = --- ; i -- ; y----z") == [
	(Number, "4"),
	(Type, "int"),
	(Keyword, "---"),
	(Keyword, "---"),
]

# A name in Unicode letters is one word, declared like any other.
expect colored_spans("π :: 3.14 // é") == [
	(Name, "π"),
	(Number, "3.14"),
	(Comment, "// é"),
]
expect colored_spans("+ - * / % = == != < <= > >= ( ) { } [ ] , ; : ! ? & | ^ ~ \\ ..") == []
