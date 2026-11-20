## CSyntax splits C source into spans, with the classes the other lexers use:
## comments (`//` and `/* */`), strings (quoted, a character, and the header
## name after `#include`, each with its `L`, `u`, `U` or `u8` prefix), numbers,
## keywords (C99's, C11's and C23's, and GCC's common spellings), types, and
## names. Other names, operators and punctuation are plain.
##
## The package has no class for the preprocessor, so a directive's `#` and its
## word (`#include`, `# define`) are one keyword span, and `defined` is a
## keyword inside one. The name a `#define` or `#undef` gives is a name.
##
## The built-in types (`int`, `unsigned`, `_Bool`), a word ending in `_t`
## (size_t, uint32_t), `FILE` and `va_list` are types, and so is the tag
## after `struct`, `union` or `enum`. A word followed by `(` outside every
## brace is a name: a function's definition or declaration, or a macro called
## at the top level. Inside braces a call is plain.
##
## A number reads as the preprocessor reads one: digits, letters, `_` and `.`
## run on, and a sign right after an exponent's `e`, `E`, `p` or `P` joins it
## (so `0x1F`, `10UL`, `1.5e-3f` and `0x1.8p3`, and `0xe+1` too, which C itself
## reads as one malformed number). A `'` between digits is C23's separator.
##
## A backslash at a line's end splices the next line on: a `//` comment, a
## string and a directive run on past it.
##
## No text makes it fail: a string or comment still open stops at its line's
## end or the text's, and a byte no token starts with is plain.
import Bytes
import Span

CSyntax :: [].{

	## The spans of `text`, covering every byte once, in order.
	spans : Str -> List(Span)
	spans = |text| {
		bytes = text.to_utf8()
		var $at = 0
		var $out = []
		var $state = {
			before: Other,
			is_in_directive: Bool.False,
			is_at_line_start: Bool.True,
			brace_depth: 0,
		}
		while $at < bytes.len() {
			token = token_at(bytes, { at: $at, state: $state })
			$out = Span.push_token(
				$out,
				{
					class: class_of(token, $state),
					start: $at,
					end: token.end,
				},
			)
			$state = next_state(token, $state)
			$at = token.end
		}
		$out
	}
}

## One token: what kind it is, and the index just past it.
Token : {
	kind : [
		Space,
		Newline,
		Splice,
		Comment,
		String,
		Number,
		Directive(Str),
		Word({ text : Str, is_before_paren : Bool }),
		OpenBrace,
		CloseBrace,
		Symbol,
	],
	end : U64,
}

## How the lexer stands between two tokens: what the token before was, as far
## as a word cares; whether a directive's line is being read; whether only
## space has come since the line began; and how many braces are open.
State : {
	before : Before,
	is_in_directive : Bool,
	is_at_line_start : Bool,
	brace_depth : U64,
}

## What the token before was: `struct`, `union` or `enum`, after which a word
## is a tag; `#define` or `#undef`, after which it is the macro's name;
## `#include`, after which a `<` opens a header's name; or anything else.
Before : [TagKeyword, DefineDirective, IncludeDirective, Other]

## C's keywords, but the type specifiers, which are types here; the values
## `true`, `false`, `nullptr` and `NULL`; and GCC's common spellings.
keywords : List(Str)
keywords = [
	"NULL",
	"_Alignas",
	"_Alignof",
	"_Atomic",
	"_Generic",
	"_Noreturn",
	"_Pragma",
	"_Static_assert",
	"_Thread_local",
	"__asm__",
	"__attribute__",
	"__extension__",
	"__inline",
	"__inline__",
	"__restrict",
	"__restrict__",
	"__typeof__",
	"__volatile__",
	"alignas",
	"alignof",
	"asm",
	"auto",
	"break",
	"case",
	"const",
	"constexpr",
	"continue",
	"default",
	"do",
	"else",
	"enum",
	"extern",
	"false",
	"for",
	"goto",
	"if",
	"inline",
	"nullptr",
	"register",
	"restrict",
	"return",
	"sizeof",
	"static",
	"static_assert",
	"struct",
	"switch",
	"thread_local",
	"true",
	"typedef",
	"typeof",
	"typeof_unqual",
	"union",
	"volatile",
	"while",
]

## The type specifiers, and the library's types whose names don't end in `_t`.
type_names : List(Str)
type_names = [
	"FILE",
	"_BitInt",
	"_Bool",
	"_Complex",
	"_Decimal128",
	"_Decimal32",
	"_Decimal64",
	"_Imaginary",
	"bool",
	"char",
	"double",
	"float",
	"int",
	"long",
	"short",
	"signed",
	"unsigned",
	"va_list",
	"void",
]

## The operators a directive's condition holds, which are keywords there.
directive_operators : List(Str)
directive_operators = ["__has_c_attribute", "__has_embed", "__has_include", "defined"]

## The prefixes a string or a character may have.
string_prefixes : List(Str)
string_prefixes = ["L", "U", "u", "u8"]

## Whether `word` names a type: one of the list, or a word ending in `_t`, as
## the C library and POSIX name theirs.
is_type_name : Str -> Bool
is_type_name = |word|
	type_names.contains(word) or (word.ends_with("_t") and word.count_utf8_bytes() > 2)

## The class of a token, given the state before it.
class_of : Token, State -> Span.Class
class_of = |token, state| match token.kind {
	Space | Newline | Splice | OpenBrace | CloseBrace | Symbol => Plain
	Comment => Comment
	String => String
	Number => Number
	Directive(_) => Keyword
	Word({ text, is_before_paren }) =>
		if state.before == DefineDirective {
			Name
		} else if state.is_in_directive and directive_operators.contains(text) {
			Keyword
		} else if is_type_name(text) {
			Type
		} else if keywords.contains(text) {
			Keyword
		} else if state.before == TagKeyword {
			Type
		} else if is_before_paren and state.brace_depth == 0 and !state.is_in_directive {
			Name
		} else {
			Plain
		}
}

## The state after `token`. Space, a splice and comments leave what came before
## as it was; a newline ends a directive; braces outside directives count.
next_state : Token, State -> State
next_state = |token, state| match token.kind {
	Space | Splice | Comment => state
	Newline => {
		before = if state.is_in_directive {
			Other
		} else {
			state.before
		}
		{
			..state,
			before,
			is_in_directive: Bool.False,
			is_at_line_start: Bool.True,
		}
	}
	Directive(word) => {
		..past_token(state),
		before: directive_before(word),
		is_in_directive: Bool.True,
	}
	Word({ text, is_before_paren: _ }) =>
		if ["struct", "union", "enum"].contains(text) {
			{ ..past_token(state), before: TagKeyword }
		} else {
			past_token(state)
		}
	OpenBrace if !state.is_in_directive => {
		..past_token(state),
		brace_depth: state.brace_depth + 1,
	}
	CloseBrace if !state.is_in_directive and state.brace_depth > 0 => {
		..past_token(state),
		brace_depth: state.brace_depth - 1,
	}
	OpenBrace | CloseBrace | String | Number | Symbol => past_token(state)
}

## The state past a token that isn't space: nothing special before the next
## one, and the line's start passed.
past_token : State -> State
past_token = |state| { ..state, before: Other, is_at_line_start: Bool.False }

## What a directive's word makes of the word after it.
directive_before : Str -> Before
directive_before = |word|
	if word == "define" or word == "undef" {
		DefineDirective
	} else if ["include", "include_next", "import", "embed"].contains(word) {
		IncludeDirective
	} else {
		Other
	}

## The token that starts at `at`, which is below the length.
token_at : List(U8), { at : U64, state : State } -> Token
token_at = |bytes, { at, state }| {
	byte = Bytes.byte_at(bytes, at)
	next = Bytes.byte_at(bytes, at + 1)
	if byte == '\n' {
		{ kind: Newline, end: at + 1 }
	} else if byte == '\\' and next == '\n' {
		{ kind: Splice, end: at + 2 }
	} else if byte == '\\' and next == '\r' and Bytes.byte_at(bytes, at + 2) == '\n' {
		{ kind: Splice, end: at + 3 }
	} else if Bytes.is_space(byte) or byte == 0x0B or byte == 0x0C {
		{ kind: Space, end: at + 1 }
	} else if byte == '/' and next == '/' {
		{ kind: Comment, end: spliced_line_end(bytes, at) }
	} else if byte == '/' and next == '*' {
		{ kind: Comment, end: Bytes.block_comment_end(bytes, at + 2) }
	} else if byte == '"' or byte == '\'' {
		{ kind: String, end: Bytes.continued_quoted_end(bytes, { at: at + 1, quote: byte }) }
	} else if byte == '<' and state.before == IncludeDirective {
		{ kind: String, end: header_name_end(bytes, at + 1) }
	} else if byte == '#' and state.is_at_line_start {
		directive_at(bytes, at)
	} else if Bytes.is_digit(byte) or (byte == '.' and Bytes.is_digit(next)) {
		{ kind: Number, end: number_end(bytes, at) }
	} else if Bytes.is_ascii_word_start(byte) {
		word_at(bytes, at)
	} else if byte == '{' {
		{ kind: OpenBrace, end: at + 1 }
	} else if byte == '}' {
		{ kind: CloseBrace, end: at + 1 }
	} else if byte >= 0x80 {
		{ kind: Symbol, end: Bytes.run_end(bytes, { at, keep: |run_byte| run_byte >= 0x80 }) }
	} else {
		{ kind: Symbol, end: at + 1 }
	}
}

## The word at `at`, or a string when the word is a string's prefix with its
## quote right after it.
word_at : List(U8), U64 -> Token
word_at = |bytes, at| {
	end = Bytes.run_end(bytes, { at, keep: Bytes.is_ascii_word_byte })
	text = word_between(bytes, { start: at, end })
	quote = Bytes.byte_at(bytes, end)
	if (quote == '"' or quote == '\'') and string_prefixes.contains(text) {
		{ kind: String, end: Bytes.continued_quoted_end(bytes, { at: end + 1, quote }) }
	} else {
		after_space = Bytes.run_end(bytes, { at: end, keep: |space| space == ' ' or space == '\t' })
		{ kind: Word({ text, is_before_paren: Bytes.byte_at(bytes, after_space) == '(' }), end }
	}
}

## The directive whose `#` is at `at`: the `#`, then its word after any spaces
## or tabs. A `#` with no word after it is the directive alone.
directive_at : List(U8), U64 -> Token
directive_at = |bytes, at| {
	start = Bytes.run_end(bytes, { at: at + 1, keep: |space| space == ' ' or space == '\t' })
	end = Bytes.run_end(bytes, { at: start, keep: Bytes.is_ascii_word_byte })
	if end == start {
		{ kind: Directive(""), end: at + 1 }
	} else {
		{ kind: Directive(word_between(bytes, { start, end })), end }
	}
}

## The word from `start` up to `end`, which holds ASCII word bytes alone.
word_between : List(U8), { start : U64, end : U64 } -> Str
word_between = |bytes, { start, end }|
	Str.from_utf8(
		bytes.sublist({ start, len: end - start }),
	) ?? crash "CSyntax.word_between: a word is ASCII"

## The end of a header's name whose text starts at `at`: past its `>`, or where
## its line or the text ends.
header_name_end : List(U8), U64 -> U64
header_name_end = |bytes, at| {
	close = Bytes.run_end(bytes, { at, keep: |name_byte| name_byte != '>' and name_byte != '\n' })
	if Bytes.byte_at(bytes, close) == '>' {
		close + 1
	} else {
		close
	}
}

## The end of the line at `at`, a line a backslash splices on included: the
## index of the first newline no backslash comes right before, or the length.
spliced_line_end : List(U8), U64 -> U64
spliced_line_end = |bytes, at| {
	var $at = at
	var $end = bytes.len()
	while $at < bytes.len() {
		byte = Bytes.byte_at(bytes, $at)
		next = Bytes.byte_at(bytes, $at + 1)
		if byte == '\n' {
			$end = $at
			$at = bytes.len()
		} else if byte == '\\' and next == '\n' {
			$at = $at + 2
		} else if byte == '\\' and next == '\r' and Bytes.byte_at(bytes, $at + 2) == '\n' {
			$at = $at + 3
		} else {
			$at = $at + 1
		}
	}
	$end
}

## The end of the number whose first byte is at `at`, as the preprocessor reads
## one (a pp-number): letters, digits, `_` and `.` run on, a `+` or `-` right
## after an exponent's letter joins it, and so does a `'` with a letter or a
## digit after it.
number_end : List(U8), U64 -> U64
number_end = |bytes, at| {
	var $at = at + 1
	var $end = bytes.len()
	while $at < bytes.len() {
		byte = Bytes.byte_at(bytes, $at)
		next = Bytes.byte_at(bytes, $at + 1)
		if is_exponent_mark(byte) and (next == '+' or next == '-') {
			$at = $at + 2
		} else if Bytes.is_ascii_word_byte(byte) or byte == '.' {
			$at = $at + 1
		} else if byte == '\'' and Bytes.is_ascii_word_byte(next) {
			$at = $at + 2
		} else {
			$end = $at
			$at = bytes.len()
		}
	}
	$end
}

## An exponent's letter: `e` or `E` for a decimal number, `p` or `P` for a
## hexadecimal one.
is_exponent_mark : U8 -> Bool
is_exponent_mark = |byte| byte == 'e' or byte == 'E' or byte == 'p' or byte == 'P'
