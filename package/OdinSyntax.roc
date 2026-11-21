## OdinSyntax splits Odin source into spans as Odin's own tokenizer reads it
## (core/odin/tokenizer in Odin's repository), with the classes the other
## lexers use: comments (`//`, `#!` and `/* */`, which nest), strings (quoted,
## a rune, a raw string in backticks, and each of those two quoted three times
## over, `"""` and three backticks), numbers, keywords, types and names. Other
## names, operators and punctuation are plain.
##
## The package has no class for directives or attributes, so a directive
## (`#partial`, `#no_bounds_check`), a file's tag (`#+build linux`, to its
## line's end), an attribute (`@private`, and the `@` of `@(...)` with each
## attribute named in its list), `---` and the values `nil`, `true` and
## `false` are keywords. The built-in types (`int`, `u8`, `f32le`, `string`,
## `rawptr`, and `typeid`, which the tokenizer reads as a keyword) are types,
## and so is a polymorphic parameter's `$T`. A word right before `::`, a
## constant's declaration, is a name: a procedure's, a type's or a value's.
##
## A word right after a `.` is a field or an enum's member, never a keyword or
## a type: `.Ident` and `info.string` are plain.
##
## A number reads as the tokenizer reads one: digits with `_`, a base's prefix
## (`0b`, `0o`, `0d`, `0z`, `0x`, and `0h` for a float's bits), a fraction
## unless `..` follows, an exponent, and `i`, `j` or `k` for an imaginary or a
## quaternion's part.
##
## No text makes it fail: a string, a rune or a comment still open stops at
## its line's end (a raw string and a comment at the text's), and a byte no
## token starts with is plain.
import Bytes
import Span

OdinSyntax :: [].{

	## The spans of `text`, covering every byte once, in order.
	spans : Str -> List(Span)
	spans = |text| {
		bytes = text.to_utf8()
		var $at = 0
		var $out = []
		var $state = { before: Other, attribute_depth: 0 }
		while $at < bytes.len() {
			token = token_at(bytes, $at)
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
		Comment,
		String,
		Number,
		Directive,
		Attribute,
		AttributeMark,
		Polymorphic,
		Undefined,
		Word({ text : Str, is_declared : Bool }),
		Dot,
		Equals,
		OpenParen,
		CloseParen,
		Symbol,
	],
	end : U64,
}

## How the lexer stands between two tokens: what the token before was, as far
## as a word cares, and how deep in an attribute's parentheses it is, 0
## outside one and 1 in its list.
State : { before : Before, attribute_depth : U64 }

## What the token before was: a `.`, after which a word is a field; an `=`,
## after which a word in an attribute's list is its value; the `@` of an
## attribute, whose `(` opens its list; or anything else.
Before : [Dot, Equals, AttributeMark, Other]

## Odin's keywords, as the tokenizer's token.odin lists them, but `typeid`,
## which is a type here; and the three values Odin reads as names.
keywords : List(Str)
keywords = [
	"asm",
	"auto_cast",
	"bit_field",
	"bit_set",
	"break",
	"case",
	"cast",
	"context",
	"continue",
	"defer",
	"distinct",
	"do",
	"dynamic",
	"else",
	"enum",
	"fallthrough",
	"false",
	"for",
	"foreign",
	"if",
	"import",
	"in",
	"map",
	"matrix",
	"nil",
	"not_in",
	"or_break",
	"or_continue",
	"or_else",
	"or_return",
	"package",
	"proc",
	"return",
	"struct",
	"switch",
	"transmute",
	"true",
	"union",
	"using",
	"when",
	"where",
]

## The built-in types: those of one size, `byte` (an alias of `u8`) and
## `typeid` among them, and the sized ones, each integer and float of two
## bytes or more in its little- and big-endian forms too (`u32le`, `f64be`).
type_names : List(Str)
type_names = List.concat(
	[
		"any",
		"b8",
		"b16",
		"b32",
		"b64",
		"bool",
		"byte",
		"complex32",
		"complex64",
		"complex128",
		"cstring",
		"cstring16",
		"i8",
		"int",
		"quaternion64",
		"quaternion128",
		"quaternion256",
		"rawptr",
		"rune",
		"string",
		"string16",
		"typeid",
		"u8",
		"uint",
		"uintptr",
	],
	["i16", "i32", "i64", "i128", "u16", "u32", "u64", "u128", "f16", "f32", "f64"]
		.join_map(|name| [name, "${name}le", "${name}be"]),
)

## The class of a token, given the state before it.
class_of : Token, State -> Span.Class
class_of = |token, state| match token.kind {
	Space | Dot | Equals | OpenParen | CloseParen | Symbol => Plain
	Comment => Comment
	String => String
	Number => Number
	Directive | Attribute | AttributeMark | Undefined => Keyword
	Polymorphic => Type
	Word({ text, is_declared }) =>
		if state.before == Dot {
			Plain
		} else if state.attribute_depth == 1 and state.before != Equals {
			Keyword
		} else if is_declared {
			Name
		} else if type_names.contains(text) {
			Type
		} else if keywords.contains(text) {
			Keyword
		} else {
			Plain
		}
}

## The state after `token`. Space and comments leave it as it was; an
## attribute's `@` makes the `(` after it open its list, and inside the list
## parentheses count.
next_state : Token, State -> State
next_state = |token, state| match token.kind {
	Space | Comment => state
	Dot => { ..state, before: Dot }
	Equals => { ..state, before: Equals }
	AttributeMark => { ..state, before: AttributeMark }
	OpenParen if state.before == AttributeMark => { before: Other, attribute_depth: 1 }
	OpenParen if state.attribute_depth > 0 => {
		before: Other,
		attribute_depth: state.attribute_depth + 1,
	}
	CloseParen if state.attribute_depth > 0 => {
		before: Other,
		attribute_depth: state.attribute_depth - 1,
	}
	OpenParen | CloseParen | Directive | Attribute | Polymorphic | Undefined => past_token(state)
	String | Number | Word(_) | Symbol => past_token(state)
}

## The state past a token that isn't space: nothing special before the next
## one.
past_token : State -> State
past_token = |state| { ..state, before: Other }

## The token that starts at `at`, which is below the length.
token_at : List(U8), U64 -> Token
token_at = |bytes, at| {
	byte = Bytes.byte_at(bytes, at)
	next = Bytes.byte_at(bytes, at + 1)
	if Bytes.is_space(byte) {
		{ kind: Space, end: at + 1 }
	} else if byte == '/' and next == '/' {
		{ kind: Comment, end: Bytes.line_end(bytes, at) }
	} else if byte == '/' and next == '*' {
		{ kind: Comment, end: nested_comment_end(bytes, at + 2) }
	} else if byte == '#' and next == '!' {
		{ kind: Comment, end: Bytes.line_end(bytes, at) }
	} else if byte == '#' and next == '+' {
		{ kind: Directive, end: file_tag_end(bytes, at) }
	} else if byte == '"' or byte == '`' {
		{ kind: String, end: string_end(bytes, { at, quote: byte }) }
	} else if byte == '\'' {
		{ kind: String, end: Bytes.quoted_end(bytes, { at: at + 1, quote: '\'' }) }
	} else if Bytes.is_digit(byte) {
		{ kind: Number, end: number_end(bytes, at) }
	} else if byte == '.' and Bytes.is_digit(next) {
		{ kind: Number, end: exponent_end(bytes, mantissa_end(bytes, { at: at + 1, base: 10 })) }
	} else if is_word_start(byte) {
		word_at(bytes, at)
	} else if byte == '#' and is_word_start(next) {
		{ kind: Directive, end: word_end(bytes, at + 1) }
	} else if byte == '@' and is_word_start(next) {
		{ kind: Attribute, end: word_end(bytes, at + 1) }
	} else if byte == '@' {
		{ kind: AttributeMark, end: at + 1 }
	} else if byte == '$' and is_word_start(next) {
		{ kind: Polymorphic, end: word_end(bytes, at + 1) }
	} else {
		symbol_at(bytes, at)
	}
}

## The operator or punctuation at `at`: the ones a word's or an attribute's
## class depends on are their own kinds, and `..`, `..<`, `..=` and `==` are
## one symbol each, so a word after a range is no field and `==` is no `=`.
symbol_at : List(U8), U64 -> Token
symbol_at = |bytes, at| {
	byte = Bytes.byte_at(bytes, at)
	next = Bytes.byte_at(bytes, at + 1)
	after = Bytes.byte_at(bytes, at + 2)
	if byte == '-' and next == '-' and after == '-' {
		{ kind: Undefined, end: at + 3 }
	} else if byte == '.' and next == '.' and (after == '<' or after == '=') {
		{ kind: Symbol, end: at + 3 }
	} else if byte == '.' and next == '.' {
		{ kind: Symbol, end: at + 2 }
	} else if byte == '.' {
		{ kind: Dot, end: at + 1 }
	} else if byte == '=' and next == '=' {
		{ kind: Symbol, end: at + 2 }
	} else if byte == '=' {
		{ kind: Equals, end: at + 1 }
	} else if byte == '(' {
		{ kind: OpenParen, end: at + 1 }
	} else if byte == ')' {
		{ kind: CloseParen, end: at + 1 }
	} else {
		{ kind: Symbol, end: at + 1 }
	}
}

## A letter, `_`, or a byte of a character that isn't ASCII: Odin's names take
## Unicode's letters, and a run of such bytes never ends inside a character.
is_word_start : U8 -> Bool
is_word_start = |byte| Bytes.is_ascii_word_start(byte) or byte >= 0x80

## The index just past the word whose first byte is at `at`.
word_end : List(U8), U64 -> U64
word_end = |bytes, at| Bytes.run_end(bytes, { at, keep: is_word_byte })

## A byte a word goes on with: an ASCII letter, a digit, `_`, or a byte of a
## character that isn't ASCII.
is_word_byte : U8 -> Bool
is_word_byte = |byte| Bytes.is_ascii_word_byte(byte) or byte >= 0x80

## The word at `at`, and whether `::` comes after it, past spaces and tabs.
word_at : List(U8), U64 -> Token
word_at = |bytes, at| {
	end = word_end(bytes, at)
	text = Str.from_utf8(
		bytes.sublist({ start: at, len: end - at }),
	) ?? crash "OdinSyntax.word_at: a word ends where a character does"
	after_space = Bytes.run_end(bytes, { at: end, keep: |space| space == ' ' or space == '\t' })
	is_declared = bytes.sublist({ start: after_space, len: 2 }) == [':', ':']
	{ kind: Word({ text, is_declared }), end }
}

## The end of a file's tag whose `#` is at `at`: its line's end, or the start
## of a comment on its line.
file_tag_end : List(U8), U64 -> U64
file_tag_end = |bytes, at| {
	var $at = at
	var $end = bytes.len()
	while $at < bytes.len() {
		byte = Bytes.byte_at(bytes, $at)
		next = Bytes.byte_at(bytes, $at + 1)
		if byte == '\n' or (byte == '/' and (next == '/' or next == '*')) {
			$end = $at
			$at = bytes.len()
		} else {
			$at = $at + 1
		}
	}
	$end
}

## The end of a block comment whose text starts at `at`, just past its `/*`,
## as the tokenizer reads one: each `/*` inside opens one more, each `*/`
## closes one, and it ends past the `*/` that closes the first, or at the
## text's end. The `*` that opens a `/*` may close a `*/` too, so `/*/`
## inside opens one and closes it, as in the tokenizer.
nested_comment_end : List(U8), U64 -> U64
nested_comment_end = |bytes, at| {
	var $at = at
	var $depth = 1
	var $end = bytes.len()
	while $at < bytes.len() {
		byte = Bytes.byte_at(bytes, $at)
		next = Bytes.byte_at(bytes, $at + 1)
		if byte == '/' and next == '*' {
			$depth = $depth + 1
			$at = $at + 1
		} else if byte == '*' and next == '/' and $depth == 1 {
			$end = $at + 2
			$at = bytes.len()
		} else if byte == '*' and next == '/' {
			$depth = $depth - 1
			$at = $at + 2
		} else {
			$at = $at + 1
		}
	}
	$end
}

## The end of the string whose opening `quote`, `"` or a backtick, is at
## `at`. Three quotes open a string that runs to the next three; a quoted
## string's backslash keeps the byte after it, and a raw one has none. One
## string a quote opens ends at its line's end, a raw one only at its quote.
string_end : List(U8), { at : U64, quote : U8 } -> U64
string_end = |bytes, { at, quote }|
	if Bytes.byte_at(bytes, at + 1) == quote and Bytes.byte_at(bytes, at + 2) == quote {
		triple_quoted_end(bytes, { at: at + 3, quote })
	} else if quote == '"' {
		Bytes.quoted_end(bytes, { at: at + 1, quote })
	} else {
		raw_end = Bytes.run_end(bytes, { at: at + 1, keep: |byte| byte != quote })
		U64.min(raw_end + 1, bytes.len())
	}

## The end of a string quoted three times over whose text starts at `at`: past
## the next three of its quotes, or the text's end. In a `"""` string a
## backslash keeps the byte after it.
triple_quoted_end : List(U8), { at : U64, quote : U8 } -> U64
triple_quoted_end = |bytes, { at, quote }| {
	var $at = at
	var $end = bytes.len()
	while $at < bytes.len() {
		byte = Bytes.byte_at(bytes, $at)
		if bytes.sublist({ start: $at, len: 3 }) == [quote, quote, quote] {
			$end = $at + 3
			$at = bytes.len()
		} else if byte == '\\' and quote == '"' {
			$at = $at + 2
		} else {
			$at = $at + 1
		}
	}
	U64.min($end, bytes.len())
}

## The end of the number whose first digit is at `at`, as the tokenizer's
## scan_number reads one: a `0` and a base's letter take that base's digits,
## and then any number takes decimal digits, a fraction and an exponent.
number_end : List(U8), U64 -> U64
number_end = |bytes, at| {
	base = if Bytes.byte_at(bytes, at) == '0' {
		match Bytes.byte_at(bytes, at + 1) {
			'b' => 2
			'o' => 8
			'd' => 10
			'z' => 12
			'x' => 16
			'h' => 16
			_ => 0
		}
	} else {
		0
	}
	digits_end = if base == 0 {
		at
	} else {
		mantissa_end(bytes, { at: at + 2, base })
	}
	whole_end = mantissa_end(bytes, { at: digits_end, base: 10 })
	if Bytes.byte_at(bytes, whole_end) == '.' and Bytes.byte_at(bytes, whole_end + 1) == '.' {
		whole_end
	} else if Bytes.byte_at(bytes, whole_end) == '.' {
		exponent_end(bytes, mantissa_end(bytes, { at: whole_end + 1, base: 10 }))
	} else {
		exponent_end(bytes, whole_end)
	}
}

## The index of the first byte at or after `at` that is neither a digit below
## `base` nor `_`.
mantissa_end : List(U8), { at : U64, base : U64 } -> U64
mantissa_end = |bytes, { at, base }| {
	is_mantissa_byte = |byte| byte == '_' or digit_value(byte) < base
	Bytes.run_end(bytes, { at, keep: is_mantissa_byte })
}

## A digit's value, `a` to `f` and `A` to `F` among them, or 16 for a byte that
## is no digit.
digit_value : U8 -> U64
digit_value = |byte|
	if Bytes.is_digit(byte) {
		(byte - '0').to_u64()
	} else if byte >= 'a' and byte <= 'f' {
		(byte - 'a').to_u64() + 10
	} else if byte >= 'A' and byte <= 'F' {
		(byte - 'A').to_u64() + 10
	} else {
		16
	}

## The end of a number's tail at `at`: an exponent's `e` or `E`, its sign and
## digits, and then an imaginary part's `i`, `j` or `k`.
exponent_end : List(U8), U64 -> U64
exponent_end = |bytes, at| {
	mark = Bytes.byte_at(bytes, at)
	sign = Bytes.byte_at(bytes, at + 1)
	exponent = if mark == 'e' or mark == 'E' {
		after_mark = if sign == '+' or sign == '-' {
			at + 2
		} else {
			at + 1
		}
		mantissa_end(bytes, { at: after_mark, base: 10 })
	} else {
		at
	}
	suffix = Bytes.byte_at(bytes, exponent)
	if suffix == 'i' or suffix == 'j' or suffix == 'k' {
		exponent + 1
	} else {
		exponent
	}
}
