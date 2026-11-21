## PythonSyntax splits Python source into spans, with the classes the other
## lexers use: comments (`#`), strings (every prefix, both quotes, one or three
## of them), numbers, keywords, the built-in types, and names. Other names,
## operators and punctuation are plain. It reads Python as the language
## reference's chapter on lexical analysis says, at Python 3.15.
##
## The hard keywords, `True`, `False` and `None` among them, are keywords
## everywhere. The soft keywords are keywords only where their statement
## starts: `match` and `case` first in a statement with a subject after them
## and then a `:` outside every bracket, ending their header; `_` in a `case`
## pattern; `type` before a name and a `=` or `[`; and `lazy` before `import`
## or `from`. Elsewhere they
## are names like any other, so `match = re.match(p, s)` stays plain. The name
## after `def`, `class` or a `type` statement is a name, and so is a decorator,
## its `@` and its dotted name, first in a statement. The built-in types (`int`,
## `str`, `dict`, `type`) are types, but not after a `.`.
##
## A string is one span with its prefix (`r`, `b`, `u`, `f`, `t` and the pairs,
## in either case). An f-string or a t-string is cut where its replacement
## fields are: the text between them is a string, each field's `{` and `}`
## plain, and the code inside colored as code, nested strings with the same
## quote, comments and other f-strings included, as Python 3.12 reads them. A
## field's format spec after its `:` is a string too, with its own nested
## fields. The open strings, fields and brackets are kept as a stack.
##
## Indentation and line joining change no color: a statement starts after a
## newline outside every bracket or after a `;`, and a backslash at a line's
## end joins the next line on, so that line starts no statement.
##
## No text makes it fail: a string still open stops at its line's end, or a
## triple-quoted one at the text's, and a byte no token starts with is plain.
import Bytes
import PythonLiteral
import Span

PythonSyntax :: [].{

	## The spans of `text`, covering every byte once, in order.
	spans : Str -> List(Span)
	spans = |text| {
		bytes = text.to_utf8()
		var $state = {
			at: 0,
			out: [],
			enclosures: [],
			before: Other,
			is_at_statement_start: Bool.True,
			is_in_case_pattern: Bool.False,
		}
		while $state.at < bytes.len() {
			$state =
				match $state.enclosures.last() {
					Ok(Text(quoting)) => text_part(
						bytes,
						{ state: $state, from: $state.at, quoting },
					)
					Ok(Spec(quoting)) => spec_part(bytes, { state: $state, quoting })
					_ => code_step(bytes, $state)
				}
		}
		$state.out
	}
}

## How the lexer stands between two tokens: the spans so far, what is open,
## what the token before was, whether a statement starts here, and whether a
## `case` line's pattern is being read.
State : {
	at : U64,
	out : List(Span),
	enclosures : List(Enclosure),
	before : Before,
	is_at_statement_start : Bool,
	is_in_case_pattern : Bool,
}

## What is open: a bracket in code; the text of an f-string or a t-string; a
## replacement field's code in one; or a field's format spec.
Enclosure : [
	Bracket,
	Text(PythonLiteral.Quoting),
	Field(PythonLiteral.Quoting),
	Spec(PythonLiteral.Quoting),
]

## What the token before was, as far as a word cares: `def`, `class` or a
## `type` statement's keyword, after which a word is a name; a `.`, after which
## a word is an attribute; or anything else.
Before : [Declarer, Dot, Other]

## Python's hard keywords.
keywords : List(Str)
keywords = [
	"False",
	"None",
	"True",
	"and",
	"as",
	"assert",
	"async",
	"await",
	"break",
	"class",
	"continue",
	"def",
	"del",
	"elif",
	"else",
	"except",
	"finally",
	"for",
	"from",
	"global",
	"if",
	"import",
	"in",
	"is",
	"lambda",
	"nonlocal",
	"not",
	"or",
	"pass",
	"raise",
	"return",
	"try",
	"while",
	"with",
	"yield",
]

## The built-in types.
type_names : List(Str)
type_names = [
	"bool",
	"bytearray",
	"bytes",
	"complex",
	"dict",
	"float",
	"frozenset",
	"int",
	"list",
	"memoryview",
	"object",
	"range",
	"set",
	"slice",
	"str",
	"tuple",
	"type",
]

## A string's prefixes, lowercased: Python takes them in either case.
string_prefixes : List(Str)
string_prefixes = ["b", "br", "f", "fr", "r", "rb", "rf", "rt", "t", "tr", "u"]

## The state with the bytes from `at` up to `end` added as one span of
## `class`, and the rest of the state as it was: space and comments.
emit : State, { class : Span.Class, end : U64 } -> State
emit = |state, { class, end }| {
	..state,
	out: Span.push_token(state.out, { class, start: state.at, end }),
	at: end,
}

## The state with a token that isn't space added: nothing special before the
## next one, and no statement starting there.
token : State, { class : Span.Class, end : U64 } -> State
token = |state, run| {
	..emit(state, run),
	before: Other,
	is_at_statement_start: Bool.False,
}

## The state after the token of code at `at`.
code_step : List(U8), State -> State
code_step = |bytes, state| {
	at = state.at
	byte = Bytes.byte_at(bytes, at)
	next = Bytes.byte_at(bytes, at + 1)
	if byte == '\n' {
		newline(emit(state, { class: Plain, end: at + 1 }))
	} else if byte == '\\' and next == '\n' {
		emit(state, { class: Plain, end: at + 2 })
	} else if byte == '\\' and next == '\r' and Bytes.byte_at(bytes, at + 2) == '\n' {
		emit(state, { class: Plain, end: at + 3 })
	} else if Bytes.is_space(byte) or byte == 0x0C {
		emit(state, { class: Plain, end: at + 1 })
	} else if byte == '#' {
		emit(state, { class: Comment, end: Bytes.line_end(bytes, at) })
	} else if byte == '"' or byte == '\'' {
		string_step(bytes, { state, quote_at: at, prefix: "" })
	} else if Bytes.is_digit(byte) or (byte == '.' and Bytes.is_digit(next)) {
		token(state, { class: Number, end: PythonLiteral.number_end(bytes, at) })
	} else if is_word_byte(byte) {
		word_step(bytes, state)
	} else if byte == '@' and state.is_at_statement_start {
		end = decorator_end(bytes, at)
		class = if end == at + 1 {
			Plain
		} else {
			Name
		}
		token(state, { class, end })
	} else if byte == '(' or byte == '[' or byte == '{' {
		{
			..token(state, { class: Plain, end: at + 1 }),
			enclosures: state.enclosures.append(Bracket),
		}
	} else if byte == ')' or byte == ']' or byte == '}' {
		closing(state, byte)
	} else if byte == ':' {
		after = token(state, { class: Plain, end: at + 1 })
		match state.enclosures.last() {
			Ok(Field(quoting)) => { ..after, enclosures: state.enclosures.append(Spec(quoting)) }
			_ => after
		}
	} else if byte == ';' and state.enclosures.is_empty() {
		{
			..token(state, { class: Plain, end: at + 1 }),
			is_at_statement_start: Bool.True,
			is_in_case_pattern: Bool.False,
		}
	} else if byte == '.' and next == '.' {
		token(state, { class: Plain, end: Bytes.run_end(bytes, { at, keep: |dot| dot == '.' }) })
	} else if byte == '.' {
		{ ..token(state, { class: Plain, end: at + 1 }), before: Dot }
	} else {
		token(state, { class: Plain, end: at + 1 })
	}
}

## The state past a newline: outside every bracket it ends the statement, and
## inside one it is space.
newline : State -> State
newline = |state|
	if state.enclosures.is_empty() {
		{
			..state,
			before: Other,
			is_at_statement_start: Bool.True,
			is_in_case_pattern: Bool.False,
		}
	} else {
		state
	}

## The state past a closing bracket: it closes the bracket open, or a `}` the
## replacement field open, and is plain alone.
closing : State, U8 -> State
closing = |state, byte| {
	closed = token(state, { class: Plain, end: state.at + 1 })
	match state.enclosures.last() {
		Ok(Bracket) => { ..closed, enclosures: state.enclosures.drop_last(1) }
		Ok(Field(_)) if byte == '}' => { ..closed, enclosures: state.enclosures.drop_last(1) }
		_ => closed
	}
}

## A word: a string's prefix with its quote right after it, or a word whose
## class the words around it decide.
word_step : List(U8), State -> State
word_step = |bytes, state| {
	at = state.at
	end = Bytes.run_end(bytes, { at, keep: is_word_byte })
	word = Str.from_utf8(
		bytes.sublist({ start: at, len: end - at }),
	) ?? crash "PythonSyntax.word_step: a word holds whole characters"
	quote = Bytes.byte_at(bytes, end)
	prefix = lowered_prefix(word)
	if (quote == '"' or quote == '\'') and string_prefixes.contains(prefix) {
		string_step(bytes, { state, quote_at: end, prefix })
	} else if state.before == Declarer {
		token(state, { class: Name, end })
	} else if keywords.contains(word) {
		before = if word == "def" or word == "class" {
			Declarer
		} else {
			Other
		}
		{ ..token(state, { class: Keyword, end }), before }
	} else if state.is_at_statement_start and is_soft_keyword_at(bytes, { word, end }) {
		before = if word == "type" {
			Declarer
		} else {
			Other
		}
		{
			..token(state, { class: Keyword, end }),
			before,
			is_in_case_pattern: word == "case",
		}
	} else if word == "_" and state.is_in_case_pattern {
		token(state, { class: Keyword, end })
	} else if state.before != Dot and type_names.contains(word) {
		token(state, { class: Type, end })
	} else {
		token(state, { class: Plain, end })
	}
}

## The word lowercased, when it is short enough to be a string's prefix; else
## the word as it is.
lowered_prefix : Str -> Str
lowered_prefix = |word|
	if word.count_utf8_bytes() > 2 {
		word
	} else {
		lowered = word.to_utf8().map(
			|byte|
				if byte >= 'A' and byte <= 'Z' {
					byte + 32
				} else {
					byte
				},
		)
		Str.from_utf8(lowered) ?? crash "PythonSyntax.lowered_prefix: lowering keeps ASCII whole"
	}

## Whether `word`, first in its statement and ending at `end`, is a soft
## keyword there: `match` or `case` with a subject after it and a `:` ending
## its header, `type` before a name and a `=` or `[`, or `lazy` before `import`
## or `from`.
is_soft_keyword_at : List(U8), { word : Str, end : U64 } -> Bool
is_soft_keyword_at = |bytes, { word, end }| {
	after = Bytes.run_end(bytes, { at: end, keep: is_blank })
	next = Bytes.byte_at(bytes, after)
	if word == "match" or word == "case" {
		is_subject_start(next) and is_header_from(bytes, after)
	} else if word == "type" and after > end and is_word_byte(next) {
		name_end = Bytes.run_end(bytes, { at: after, keep: is_word_byte })
		mark_at = Bytes.run_end(bytes, { at: name_end, keep: is_blank })
		mark = Bytes.byte_at(bytes, mark_at)
		mark == '[' or (mark == '=' and Bytes.byte_at(bytes, mark_at + 1) != '=')
	} else if word == "lazy" and after > end {
		next_end = Bytes.run_end(bytes, { at: after, keep: is_word_byte })
		next_word = bytes.sublist({ start: after, len: next_end - after })
		next_word == "import".to_utf8() or next_word == "from".to_utf8()
	} else {
		Bool.False
	}
}

## Whether a `match` or `case` subject can start with `byte`: a word, a number,
## a string, a bracket, or a sign or `*` before one.
is_subject_start : U8 -> Bool
is_subject_start = |byte|
	is_word_byte(byte) or "\"'([{-*~".to_utf8().contains(byte)

## Whether the line from `at` holds a `:` outside every bracket, as a compound
## statement's header does: its brackets may run on over lines, and a quoted
## string or a comment holds none.
is_header_from : List(U8), U64 -> Bool
is_header_from = |bytes, at| {
	var $at = at
	var $depth = 0
	var $is_header = Bool.False
	while $at < bytes.len() {
		byte = Bytes.byte_at(bytes, $at)
		if (byte == ':' or byte == '\n') and $depth == 0 {
			$is_header = byte == ':'
			$at = bytes.len()
		} else if byte == '"' or byte == '\'' {
			$at = Bytes.quoted_end(bytes, { at: $at + 1, quote: byte })
		} else if byte == '#' {
			$at = Bytes.line_end(bytes, $at)
		} else {
			$depth = bracket_depth_after(byte, $depth)
			$at = $at + 1
		}
	}
	$is_header
}

## The number of brackets open after `byte`, `depth` of them open before it.
bracket_depth_after : U8, U64 -> U64
bracket_depth_after = |byte, depth|
	if byte == '(' or byte == '[' or byte == '{' {
		depth + 1
	} else if (byte == ')' or byte == ']' or byte == '}') and depth > 0 {
		depth - 1
	} else {
		depth
	}

## The string whose opening quote is at `quote_at`, `prefix` (lowercased)
## before it from the state's `at`: one span, or for an f-string or a t-string,
## its text up to its first field.
string_step : List(U8),
{
	state : State,
	quote_at : U64,
	prefix : Str,
} -> State
string_step = |bytes, { state, quote_at, prefix }| {
	quoting = PythonLiteral.quoting_at(bytes, { quote_at, prefix })
	text_at = quote_at + PythonLiteral.quote_length(quoting)
	if prefix.contains("f") or prefix.contains("t") {
		opened = { ..state, enclosures: state.enclosures.append(Text(quoting)) }
		text_part(bytes, { state: opened, from: text_at, quoting })
	} else {
		token(
			state,
			{ class: String, end: PythonLiteral.plain_string_end(bytes, { at: text_at, quoting }) },
		)
	}
}

## The state after a part of an f-string's text, from `from` up to what ends
## it: its closing quote, a field's `{`, or its line's or the text's end.
text_part : List(U8),
{
	state : State,
	from : U64,
	quoting : PythonLiteral.Quoting,
} -> State
text_part = |bytes, { state, from, quoting }| {
	stop = PythonLiteral.text_stop(bytes, { at: from, quoting, kind: Formatted })
	text = token(state, { class: String, end: stop.at })
	match stop.kind {
		Quote => {
			..token(state, { class: String, end: stop.at + PythonLiteral.quote_length(quoting) }),
			enclosures: state.enclosures.drop_last(1),
		}
		OpenField => {
			..token(text, { class: Plain, end: stop.at + 1 }),
			enclosures: state.enclosures.append(Field(quoting)),
		}
		CloseField | LineEnd | TextEnd => { ..text, enclosures: state.enclosures.drop_last(1) }
	}
}

## The state after a part of a format spec, from the state's `at` up to what
## ends it: a nested field's `{`, its own field's `}`, or what ends the string.
spec_part : List(U8), { state : State, quoting : PythonLiteral.Quoting } -> State
spec_part = |bytes, { state, quoting }| {
	stop = PythonLiteral.text_stop(bytes, { at: state.at, quoting, kind: FormatSpec })
	text = token(state, { class: String, end: stop.at })
	match stop.kind {
		Quote => {
			..token(state, { class: String, end: stop.at + PythonLiteral.quote_length(quoting) }),
			enclosures: enclosures_outside_text(state.enclosures),
		}
		OpenField => {
			..token(text, { class: Plain, end: stop.at + 1 }),
			enclosures: state.enclosures.append(Field(quoting)),
		}
		CloseField => {
			..token(text, { class: Plain, end: stop.at + 1 }),
			enclosures: state.enclosures.drop_last(2),
		}
		LineEnd | TextEnd => { ..text, enclosures: enclosures_outside_text(state.enclosures) }
	}
}

## The enclosures with the innermost f-string's text closed, and all open in it.
enclosures_outside_text : List(Enclosure) -> List(Enclosure)
enclosures_outside_text = |enclosures| match enclosures.last() {
	Ok(Text(_)) => enclosures.drop_last(1)
	Ok(_) => enclosures_outside_text(enclosures.drop_last(1))
	Err(ListWasEmpty) => enclosures
}

## The end of a decorator whose `@` is at `at`: past its dotted name, after any
## spaces; just past the `@` when no name follows.
decorator_end : List(U8), U64 -> U64
decorator_end = |bytes, at| {
	start = Bytes.run_end(bytes, { at: at + 1, keep: is_blank })
	end = Bytes.run_end(
		bytes,
		{ at: start, keep: |name_byte| is_word_byte(name_byte) or name_byte == '.' },
	)
	if end == start {
		at + 1
	} else {
		end
	}
}

## A space or a tab, between the words of a line.
is_blank : U8 -> Bool
is_blank = |byte| byte == ' ' or byte == '\t'

## A byte of a name: an ASCII letter, a digit, `_`, or any byte of a character
## past ASCII, which Python's names may hold. A digit never starts one, since
## a number is read first.
is_word_byte : U8 -> Bool
is_word_byte = |byte| Bytes.is_ascii_word_byte(byte) or byte >= 0x80
