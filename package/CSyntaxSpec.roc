## CSyntaxSpec holds CSyntax to C as its header says it reads: comments,
## strings, numbers, directives, keywords, types and names, each with the near
## misses that must stay plain. The tests live here, outside the lexer, so the
## lexer's module stays small.
import CSyntax
import Span

CSyntaxSpec :: [].{}

## The runs of `text` that get a color, each with its class and its text: what
## the expects below read.
colored_spans : Str -> List((Span.Class, Str))
colored_spans = |text| {
	bytes = text.to_utf8()
	CSyntax.spans(text)
		.keep_if(|span| span.class != Plain)
		.map(
			|span| (
				span.class,
				Str.from_utf8(
					bytes.sublist({ start: span.start, len: span.end - span.start }),
				) ?? crash "CSyntaxSpec.colored_spans: a span cuts a character",
			),
		)
}

## The colored runs of the lines, a newline after each but the last.
colored_lines : List(Str) -> List((Span.Class, Str))
colored_lines = |lines| colored_spans(Str.join_with(lines, "\n"))

## The words of the pieces, each piece a run of words apart by spaces.
words_of : List(Str) -> List(Str)
words_of = |pieces| pieces.join_map(|piece| piece.split_on(" "))

expect CSyntax.spans("") == []

# Comments of both kinds, one never closed, a spliced line comment, and a `/*/`
# that doesn't close itself.
expect colored_lines(["a // b /* c", "/* d", "e */ f"]) == [
	(Comment, "// b /* c"),
	(Comment, "/* d\ne */"),
]
expect colored_spans("// a \\\nb\nc /* d") == [(Comment, "// a \\\nb"), (Comment, "/* d")]
expect colored_spans("/*/ x */ y / z") == [(Comment, "/*/ x */")]

# Strings and characters with escapes and prefixes, a spliced string, and one
# still open, which stops at its line's end.
expect colored_spans("f(\"a\\\"b\\\\\", 'c', '\\'', '\\n', \"\\x41\\0\")") == [
	(Name, "f"),
	(String, "\"a\\\"b\\\\\""),
	(String, "'c'"),
	(String, "'\\''"),
	(String, "'\\n'"),
	(String, "\"\\x41\\0\""),
]
expect colored_spans("L\"w\" u8\"x\" u'y' U\"z\" Lx \"a\\\nb\"") == [
	(String, "L\"w\""),
	(String, "u8\"x\""),
	(String, "u'y'"),
	(String, "U\"z\""),
	(String, "\"a\\\nb\""),
]
expect colored_spans("x = \"ab\ny = 1") == [(String, "\"ab"), (Number, "1")]

# Numbers in every base, with suffixes, fractions, exponents and separators.
expect
	colored_lines([
		"f(0, 10, 017, 0x1F, 0XffUL, 10UL, 10u, 3LL,",
		"  1.5, .5, 1.f, 1e10, 1.5e-3f, 2E+4L, 0x1.8p3, 0x1p-3,",
		"  0b1010, 1'000'000, 9abc)",
	])
		== [
			(Name, "f"),
			(Number, "0"),
			(Number, "10"),
			(Number, "017"),
			(Number, "0x1F"),
			(Number, "0XffUL"),
			(Number, "10UL"),
			(Number, "10u"),
			(Number, "3LL"),
			(Number, "1.5"),
			(Number, ".5"),
			(Number, "1.f"),
			(Number, "1e10"),
			(Number, "1.5e-3f"),
			(Number, "2E+4L"),
			(Number, "0x1.8p3"),
			(Number, "0x1p-3"),
			(Number, "0b1010"),
			(Number, "1'000'000"),
			(Number, "9abc"),
		]
expect colored_spans("a.b x[1]-1 0xe+1 1'a'") == [
	(Number, "1"),
	(Number, "1"),
	(Number, "0xe+1"),
	(Number, "1'a"),
	(String, "'"),
]

# Directives: the `#` and its word are one keyword, spaced or not, at a line's
# start only; the name a `#define` gives is a name; a header's name is a string.
expect colored_lines([
	"#include <stdio.h>",
	"  # include \"cache.h\"",
	"#define MAX(a, b) ((a) > (b))",
	"#undef MAX",
]) == [
	(Keyword, "#include"),
	(String, "<stdio.h>"),
	(Keyword, "# include"),
	(String, "\"cache.h\""),
	(Keyword, "#define"),
	(Name, "MAX"),
	(Keyword, "#undef"),
	(Name, "MAX"),
]
expect colored_lines([
	"#if defined(X) && !defined Y",
	"#elif __has_include(<a.h>)",
	"#endif // z",
	"x = defined;",
]) == [
	(Keyword, "#if"),
	(Keyword, "defined"),
	(Keyword, "defined"),
	(Keyword, "#elif"),
	(Keyword, "__has_include"),
	(Keyword, "#endif"),
	(Comment, "// z"),
]
expect colored_spans("x = a # b;\n#\n#define S(x) #x a ## b") == [
	(Keyword, "#"),
	(Keyword, "#define"),
	(Name, "S"),
]
expect colored_spans("a < b > c") == []

# A directive runs on past a splice and a comment's newline, and ends at its
# line's end, so a brace in it doesn't count.
expect colored_lines([
	"#define F(x) \\",
	"  g(x) {",
	"int f(void);",
	"#define A /* a",
	" b */ int",
]) == [
	(Keyword, "#define"),
	(Name, "F"),
	(Type, "int"),
	(Name, "f"),
	(Type, "void"),
	(Keyword, "#define"),
	(Name, "A"),
	(Comment, "/* a\n b */"),
	(Type, "int"),
]

# Every keyword, each its own span, and words that hold one.
expect
	words_of([
		"NULL _Alignas _Alignof _Atomic _Generic _Noreturn _Pragma",
		"_Static_assert _Thread_local __asm__ __attribute__ __extension__",
		"__inline __inline__ __restrict __restrict__ __typeof__ __volatile__",
		"alignas alignof asm auto break case const constexpr continue default",
		"do else enum extern false for goto if inline nullptr register",
		"restrict return sizeof static static_assert struct switch",
		"thread_local true typedef typeof typeof_unqual union volatile while",
	]).all(|word| colored_spans(word) == [(Keyword, word)])
expect colored_spans("iffy fortune _if Return null TRUE") == []

# The types, a `_t` word, the tag after `struct`, `union` or `enum`, and near
# misses.
expect
	words_of([
		"FILE _BitInt _Bool _Complex _Decimal128 _Decimal32 _Decimal64",
		"_Imaginary bool char double float int long short signed unsigned",
		"va_list void size_t uint32_t",
	]).all(|word| colored_spans(word) == [(Type, word)])
expect colored_spans("_t t integer shorts file") == []
expect colored_spans("struct cache_entry *ce; union /* u */ u; enum { A } e;") == [
	(Keyword, "struct"),
	(Type, "cache_entry"),
	(Keyword, "union"),
	(Comment, "/* u */"),
	(Type, "u"),
	(Keyword, "enum"),
]

# A word before `(` outside braces is a name; inside them, a call is plain.
expect colored_lines([
	"static int verify_hdr (struct h *hdr)",
	"{",
	"\treturn check(hdr) { f(); } g(1);",
	"}",
	"int main(void) {}",
]) == [
	(Keyword, "static"),
	(Type, "int"),
	(Name, "verify_hdr"),
	(Keyword, "struct"),
	(Type, "h"),
	(Keyword, "return"),
	(Number, "1"),
	(Type, "int"),
	(Name, "main"),
	(Type, "void"),
]
expect colored_spans("} } f(x)") == [(Name, "f")]
expect colored_spans("+ - * / % = == != < <= > >= ( ) [ ] , ; : ! ? & | ^ ~ $ @ ` \\ é") == []
