## PythonLiteral reads where Python's literals end, for PythonSyntax: a
## string's text, plain or formatted, up to what stops it, and a number.
## PythonSyntax decides what the stops mean for its open fields and brackets.
import Bytes

PythonLiteral :: [].{

	## How a string is quoted: its quote, whether there are three of it, and
	## whether it is raw, so a backslash names no character.
	Quoting : {
		quote : U8,
		is_triple : Bool,
		is_raw : Bool,
	}

	## Where the text of a string stops, and what stops it: its closing quote, a
	## field's `{`, a format spec's `}`, or its line's or the text's end.
	Stop : { at : U64, kind : [Quote, OpenField, CloseField, LineEnd, TextEnd] }

	## How the string whose opening quote is at `quote_at` is quoted, given its
	## prefix, lowercased.
	quoting_at : List(U8), { quote_at : U64, prefix : Str } -> PythonLiteral.Quoting
	quoting_at = |bytes, { quote_at, prefix }| {
		quote = Bytes.byte_at(bytes, quote_at)
		is_triple = Bytes.byte_at(
			bytes,
			quote_at + 1,
		) == quote and Bytes.byte_at(bytes, quote_at + 2) == quote
		{ quote, is_triple, is_raw: prefix.contains("r") }
	}

	## How many quotes open and close a string quoted so.
	quote_length : PythonLiteral.Quoting -> U64
	quote_length = |quoting|
		if quoting.is_triple {
			3
		} else {
			1
		}

	## The end of a string that isn't formatted, whose text starts at `at`: past
	## its closing quote, or where its line ends when it has one quote, or the
	## text's end.
	plain_string_end : List(U8), { at : U64, quoting : PythonLiteral.Quoting } -> U64
	plain_string_end = |bytes, { at, quoting }| {
		stop = PythonLiteral.text_stop(bytes, { at, quoting, kind: Plain })
		match stop.kind {
			Quote => stop.at + PythonLiteral.quote_length(quoting)
			_ => stop.at
		}
	}

	## Where a string's text from `at` stops. A plain string's stops only at its
	## closing quote, its line's end when it has one quote, or the text's end. An
	## f-string's also stops at a field's `{`, though `{{` and `}}` are text, and a
	## format spec's at any `{` or `}`. A backslash keeps the byte after it, but a
	## brace, so a quote or a newline after one is the string's.
	text_stop : List(U8),
	{
		at : U64,
		quoting : PythonLiteral.Quoting,
		kind : [Plain, Formatted, FormatSpec],
	} -> PythonLiteral.Stop
	text_stop = |bytes, { at, quoting, kind }| {
		var $at = at
		var $stop = { at: bytes.len(), kind: TextEnd }
		while $at < bytes.len() {
			byte = Bytes.byte_at(bytes, $at)
			next = Bytes.byte_at(bytes, $at + 1)
			is_brace = byte == '{' or byte == '}'
			if is_closing_quote(bytes, { at: $at, quoting }) {
				$stop = { at: $at, kind: Quote }
				$at = bytes.len()
			} else if byte == '\n' and !quoting.is_triple {
				$stop = { at: $at, kind: LineEnd }
				$at = bytes.len()
			} else if byte == '\\' {
				$at = escape_end(bytes, { at: $at, quoting })
			} else if !is_brace or kind == Plain {
				$at = $at + 1
			} else if kind == Formatted and next == byte {
				$at = $at + 2
			} else if byte == '{' {
				$stop = { at: $at, kind: OpenField }
				$at = bytes.len()
			} else if kind == FormatSpec {
				$stop = { at: $at, kind: CloseField }
				$at = bytes.len()
			} else {
				$at = $at + 1
			}
		}
		$stop
	}

	## The end of the number whose first byte is at `at`: `0x1F`, `0o17` and
	## `0b1`, or digits with a fraction and an exponent, each with `_` between
	## digits, and a decimal one with an imaginary `j`.
	number_end : List(U8), U64 -> U64
	number_end = |bytes, at| {
		is_radix = ['x', 'X', 'o', 'O', 'b', 'B'].contains(Bytes.byte_at(bytes, at + 1))
		if Bytes.byte_at(bytes, at) == '0' and is_radix {
			Bytes.run_end(bytes, { at: at + 2, keep: |digit| is_hex_digit(digit) or digit == '_' })
		} else {
			whole = Bytes.run_end(bytes, { at, keep: is_digit_or_separator })
			fraction =
				if Bytes.byte_at(bytes, whole) == '.' {
					Bytes.run_end(bytes, { at: whole + 1, keep: is_digit_or_separator })
				} else {
					whole
				}
			mark = Bytes.byte_at(bytes, fraction)
			sign = Bytes.byte_at(bytes, fraction + 1)
			is_signed = (sign == '+' or sign == '-') and Bytes.is_digit(
				Bytes.byte_at(bytes, fraction + 2),
			)
			exponent =
				if (mark == 'e' or mark == 'E') and (Bytes.is_digit(sign) or is_signed) {
					Bytes.run_end(bytes, { at: fraction + 2, keep: is_digit_or_separator })
				} else {
					fraction
				}
			suffix = Bytes.byte_at(bytes, exponent)
			if suffix == 'j' or suffix == 'J' {
				exponent + 1
			} else {
				exponent
			}
		}
	}
}

## Whether the string's closing quote, one or three, starts at `at`.
is_closing_quote : List(U8), { at : U64, quoting : PythonLiteral.Quoting } -> Bool
is_closing_quote = |bytes, { at, quoting }| {
	quote = quoting.quote
	Bytes.byte_at(bytes, at) == quote and (!quoting.is_triple
		or (Bytes.byte_at(bytes, at + 1) == quote and Bytes.byte_at(bytes, at + 2) == quote))
}

## The end of the escape whose backslash is at `at`: the byte after it too,
## unless that is a brace; or a whole `\N{...}` outside a raw string, to its
## `}`, or where its line or the string ends.
escape_end : List(U8), { at : U64, quoting : PythonLiteral.Quoting } -> U64
escape_end = |bytes, { at, quoting }| {
	next = Bytes.byte_at(bytes, at + 1)
	if next == '{' or next == '}' {
		at + 1
	} else if !quoting.is_raw and next == 'N' and Bytes.byte_at(bytes, at + 2) == '{' {
		is_in_name = |name_byte| ![quoting.quote, '}', '\n'].contains(name_byte)
		close = Bytes.run_end(bytes, { at: at + 3, keep: is_in_name })
		if Bytes.byte_at(bytes, close) == '}' {
			close + 1
		} else {
			close
		}
	} else {
		at + 2
	}
}

is_digit_or_separator : U8 -> Bool
is_digit_or_separator = |byte| Bytes.is_digit(byte) or byte == '_'

is_hex_digit : U8 -> Bool
is_hex_digit = |byte|
	Bytes.is_digit(byte) or (byte >= 'a' and byte <= 'f') or (byte >= 'A' and byte <= 'F')
