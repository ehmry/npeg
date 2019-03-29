
# NPeg

NPeg is a pure Nim pattern matching library. It provides macros to compile
patterns and grammars (PEGs) to Nim procedures which will parse a string and
collect selected parts of the input. PEGs are not unlike regular expressions,
but offer more power and flexibility, and have less ambiguities.

Some NPeg highlights:

- Grammar definitions and Nim code can be freely mixed. Nim code is embedded
  using the normal Nim code block syntax, and does not disrupt the grammar
  definition.

- NPeg-generated parsers can be used both at run and at compile time.

- NPeg offers various methods for tracing, optimizing and debugging your
  parsers.

Here is a simple example showing the power of NPeg: The macro `peg` compiles a
grammar definition into a `parser` object, which is used to match a string and
place the key-value pairs into the Nim table `words`:

```nim
import npeg, strutils, tables

var words = initTable[string, int]()

let parser = peg "pairs":
  pairs <- pair * *(',' * pair) * !1
  word <- +{'a'..'z'}
  number <- +{'0'..'9'}
  pair <- >word * '=' * >number:
    words[c[0]] = c[1].parseInt

doAssert parser.match("one=1,two=2,three=3,four=4").ok
echo words
```

Output:

```nim
{"two": 2, "three": 3, "one": 1, "four": 4}
```


## Usage

The `patt()` and `peg()` macros can be used to compile parser functions:

- `patt()` creates a parser from a single anonymous pattern

- `peg()` allows the definition of a set of (potentially recursive) rules 
          making up a complete grammar.

The result of these macros is an object of the type `Parser` which can be used
to parse a subject:

```nim
proc match(p: Parser, s: string) = MatchResult
proc match(p: Parser, s: cstring) = MatchResult
proc matchFile(p: Parser, fname: string) = MatchResult
```

The above `match` functions returns an object of the type `MatchResult`:

```nim
MatchResult = object
  ok: bool
  matchLen: int
  matchMax: int
  ...
```

* `ok`: A boolean indicating if the matching succeeded without error. Note that
  a successful match does not imply that *all of the subject* was matched,
  unless the pattern explicitly matches the end-of-string.

* `matchLen`: The number of input bytes of the subject that successfully
  matched.

* `matchMax`: The highest index into the subject that was reached during
  parsing, *even if matching was backtracked or did not succeed*. This offset
  is usually a good indication of the location where the matching error
  occured.

There are two different ways to access the matched data, which can be freely
mixed:

The following proc are available to retrieve the captured results:

```nim
proc captures(m: MatchResult): seq[string]
proc capturesJson(m: MatchResult): JsonNode
```


### Simple patterns

A simple pattern can be compiled with the `patt` macro.

For example, the pattern below splits a string by white space:

```nim
let parser = patt *(*' ' * > +(1-' '))
echo parser.match("   one two three ").captures
```

Output:

```
@["one", "two", "three"]
```


### Grammars

The `peg` macro provides a method to define (recursive) grammars. The first
argument is the name of initial patterns, followed by a list of named patterns.
Patterns can now refer to other patterns by name, allowing for recursion:

```nim
let parser = peg "ident":
  lower <- {'a'..'z'}
  ident <- *lower
doAssert parser.match("lowercaseword").ok
```


#### Ordering of rules in a grammar

The order in which the grammar patterns are defined affects the generated parser.
Although NPeg could always reorder, this is a design choice to give the user
more control over the generated parser:

* when a pattern `P1` refers to pattern `P2` which is defined *before* `P1`,
  `P2` will be inlined in `P1`.  This increases the generated code size, but
  generally improves performance.

* when a pattern `P1` refers to pattern `P2` which is defined *after* `P1`,
  `P2` will be generated as a subroutine which gets called from `P1`. This will
  reduce code size, but might also result in a slower parser.

The exact parser size and performance behavior depends on many factors; when
performance and/or code size matters, it pays to experiment with different
orderings and measure the results.



## Syntax

The NPeg syntax is similar to normal PEG notation, but some changes were made
to allow the grammar to be properly parsed by the Nim compiler:

- NPeg uses prefixes instead of suffixes for `*`, `+`, `-` and `?`
- Ordered choice uses `|` instead of `/` because of operator precedence
- The explicit `*` infix operator is used for sequences

NPeg patterns and grammars can be composed from the following parts:

```nim

Atoms:

   0            # matches always and consumes nothing
   1            # matches any character
   n            # matches exactly n characters
  'x'           # matches literal character 'x'
  "xyz"         # matches literal string "xyz"
 i"xyz"         # matches literal string, case insensitive
  {'x'..'y'}    # matches any character in the range from 'x'..'y'
  {'x','y','z'} # matches any character from the set

Operators:

   P1 * P2      # concatenation
   P1 | P2      # ordered choice
   P1 - P2      # matches P1 if P2 does not match
  (P)           # grouping
  !P            # matches everything but P
  &P            # matches P without consuming input
  ?P            # matches P zero or one times
  *P            # matches P zero or more times
  +P            # matches P one or more times
  @P            # search for P
   P[n]         # matches P n times
   P[m..n]      # matches P m to n times

String captures:

  >P            # Captures the string matching  P 

Json captures:

  Js(P)         # Produces a JString from the string matching  P 
  Ji(P)         # Produces a JInteger from the string matching  P 
  Jf(P)         # Produces a JFloat from the string matching  P 
  Ja()          # Produces a new JArray
  Jo()          # Produces a new JObject
  Jt("tag", P)  # Stores capture  P  in the field "tag" of the outer JObject
  Jt(P)         # Stores the second Json capture of  P  in the outer JObject
                # using the first Json capure of  P  as the tag.

Error handling:

  E"msg"        # Raise an execption with the given message
```

In addition to the above, NPeg provides the following built-in shortcuts for
common atoms:

```nim
  Upper        # {'A'..'Z'},
  Lower        # {'a'..'z'},
  Alpha        # {'A'..'Z','a'..'z'},
  Digit        # {'0'..'9'},
  Space        # {'\9'..'\13',' '},
  Word         # {'A'..'Z','a'..'z','0'..'9'},
  HexDigit     # {'A'..'F','a'..'f','0'..'9'},
```


### Atoms

Atoms are the basic building blocks for a grammer, describing the parts of the
subject that should be matched.

- Integer literal: `0` / `1` / `n`

  The int literal atom `N` matches exactly n number of bytes. `0` always matches,
  but does not consume any data.


- Character and string literals: `'x'` / `"xyz"` / `i"xyz"`

  Characters and strings are literally matched. If a string is prefixed with `i`,
  it will be matched case insensitive.


- Character sets: `{'x','y'}`

  Characters set notation is similar to native Nim. A set consists of zero or more
  comma separated characters or character ranges.

  ```nim
   {'x'..'y'}    # matches any character in the range from 'x'..'y'
   {'x','y','z'} # matches any character from the set 'x', 'y', and 'z'
  ```

  The set syntax `{}` is flexible and can take multiple ranges and characters in
  one expression, for example `{'0'..'9','a'..'f','A'..'F'}`.


### Operators

NPeg provides various prefix, infix and suffix operators. These operators
combine or transform one or more patterns into expressions, building larger
patterns.

- Concatenation: `P1 * P2`

  The pattern `P1 * P2` returns a new pattern that matches only if first `P1` matches,
  followed by `P2`.

  For example, `"foo" * "bar"` would only match the string `"foobar"`


- Ordered choice: `P1 | P2`

  The pattern `P1 | P2` tries to first match pattern `P1`. If this succeeds,
  matching will proceed without trying `P2`. Only if `P1` can not be matched,
  NPeg will backtrack and try to match `P2` instead.

  For example `("foo" | "bar") * "fizz"` would match both `"foofizz"` and `"barfizz"`

  NPeg optimizes the `|` operator for characters and character sets: The
  pattern `'a' | 'b' | 'c'` will be rewritten to a character set `{'a','b','c'}`


- Difference: `P1 - P2`

  The pattern `P1 - P2` matches `P1` *only* if `P2` does not match. This is
  equivalent to `!P2 * P1`

  NPeg optimizes the `-` operator for characters and character sets: The
  pattern `{'a','b','c'} - 'b'` will be rewritten to the character set `{'a','c'}


- Grouping: `(P)`

  Brackets are used to group patterns similar to normal mathematical expressions.


- Not-predicate: `!P`

  The pattern `!P` returns a pattern that matches only if the input does not match `P`.
  In contrast to most other patterns, this pattern does not consume any input.

  A common usage for this operator is the pattern `!1`, meaning "only succeed if there
  is not a single character left to match" - which is only true for the end of the string.


- And-predicate: `&P`

  The pattern `&P` matches only if the input matches `P`, but will *not*
  consume any input. This is equivalent to `!!P`


- Optional: `?P`

  The pattern `?P` matches if `P` can be matched zero or more times, so essentially
  succeeds if `P` either matches or not.

  For example, `?"foo" * bar"` matches both `"foobar"` and `"bar"`


- Match zero or more times: `*P`

  The pattern `*P` tries to match as many occurrences of pattern `P` as
  possible - this operator always behaves *greedily*.

  For example, `*"foo" * "bar"` matches `"bar"`, `"fooboar"`, `"foofoobar"`, etc


- Match one or more times: `+P`

  The pattern `+P` matches `P` at least once, but also more times. It is equivalent
  to the `P * *P` - this operator always behave *greedily*


- Search: `@P`

  This operator is syntactic sugar for the operation of searching `s <- P | 1 * s`,
  which translates to "try to match `P`, and if this fails, consume 1 byte and
  try again".

  Note that this operator does not allow capturing the skipped data up to the
  match; if his is required you can manually construct a grammar to do this.


- Match exactly `n` times: `P[n]`

  The pattern `P[n]` matches `P` exactly `n` times.

  For example, `"foo"[3]` only matches the string `"foofoofoo"`


- Match `m` to `n` times: `P[m..n]`

  The pattern `P[m..n]` matches `P` at least `m` and at most `n` times.

  For example, `"foo[1,3]"` matches `"foo"`, `"foofoo"` and `"foofoofo"`


## Captures

NPeg supports a number of ways to capture data when parsing a string. The various
capture methods are described here, including a concise example.

The capture examples below build on the following small PEG, which parses
a comma separated list of key-value pairs:

```nim
const data = "one=1,two=2,three=3,four=4"

let parser = peg "pairs":
  pairs <- pair * *(',' * pair) * !1
  word <- +{'a'..'z'}
  pair <- word * '=' * word

let r = parser.match(data)
```

### String captures

The basic method for capturing is marking parts of the peg with the capture
prefix `>`. During parsing NPeg keeps track of all matches, properly discarding
any matches which were invalidated by backtracking. Only when parsing has fully
succeeded it creates a `seq[string]` of all matched parts, which is then
returned in the `MatchData.captures` field.

In the example, the `>` capture prefix is added to the `word` rule, causing all
the matched words to be appended to the result capture `seq[string]`

```nim
let parser = peg "pairs":
  pairs <- pair * *(',' * pair) * !1
  word <- +{'a'..'z'}
  pair <- >word * '=' * >word

let r = parser.match(data)
```

The resulting list of captures is now:

```nim
@["one", "1", "two", "2", "three", "3", "four", "4"]
```


### Json captures

In order capture more complex data it is possible to mark the PEG with
operators which will build a tree of JsonNodes from the matched data.

In the example below:

- The outermost rule `pairs` gets encapsulated by the `Jo` operator, which
  produces a Json object (`JObject`).

- The `pair` rule is encapsulated in `Jt` which will produce a tagged pair
  which will be stored in its outer JObject.

- The matched `word` is captured with `Js` to produce a JString. This will
  be consumed by its outer `Jt` capture which will used it for the field name

- The matched `number` is captured with a `Ji` to produce a JInteger, which
  will be consumed by its outer `Jt` capture which will use it for the field
  value.

```nim
let parser = peg "pairs":
  pairs <- Jo(pair * *(',' * pair) * !1)
  word <- +{'a'..'z'}
  number <- +{'0'..'9'}
  pair <- Jt(Js(word) * '=' * Ji(number))

let r = parser.match(data)
echo r.capturesJson
```

The resulting Json data is now:

```json
{
  "one": 1,
  "two": 2,
  "three": 3,
  "four": 4
}
```


### Code block captures

Code block captures offer the most flexibility for accessing matched data in
NPeg. This allows you to define a grammar with embedded Nim code for handling
the data during parsing.

Note that for code block captures, the Nim code gets executed during parsing,
*even if the match is part of a pattern that fails and is later backtracked*

When a grammar rule ends with a colon `:`, the next indented block in the
grammar is interpreted as Nim code, which gets executed when the rule has been
matched. Any string captures that were made inside the rule are available to
the Nim code in the `c[]` array. Code block captures consume all embedded
string captures, so these captures will no longer be available after matching.

The example has been extended to capture each word and number with the `>`
string capture prefix. When the `pair` rule is matched, the attached code block
is executed, which adds the parsed key and value to the `words` table.

```nim
from strutils import parseInt
var words = initTable[string, int]()

let parser = peg "pairs":
  pairs <- pair * *(',' * pair) * !1
  word <- +{'a'..'z'}
  number <- +{'0'..'9'}
  pair <- >word * '=' * >number:
    words[c[0]] = c[1].parseInt

let r = parser.match(data)
```

After the parsing finished, the `words` table will now contain

```nim
{"two": 2, "three": 3, "one": 1, "four": 4}
```


## Some notes on using PEGs


### Achoring and searching

Unlike regular expressions, PEGs are always matched in *anchored* mode only: the
defined pattern is matched from the start of the subject string. For example,
the pattern `"bar"` does not match the string `"foobar"`.

To search for a pattern in a stream, a construct like this can be used:

```nim
p <- "bar"
search <- p | 1 * search
```

The above grammar first tries to match pattern `p`, or if that fails, matches
any character `1` and recurs back to itself. Because searching is a common
operation, NPeg provides the builtin `@P` operator for this.


### End of string

PEGs do not care what is in the subject string after the matching succeeds. For
example, the rule `"foo"` happily matches the string `"foobar"`. To make sure
the pattern matches the end of string, this has to be made explicit in the
pattern.

The idiomatic notation for this is `!1`, meaning "only succeed if there is not
a single character left to match" - which is only true for the end of the
string.


### Parsing error handling

NPeg offers a number of ways to handle errors during parsing a subject string:

The `ok` field in the `MatchResult` indicates if the parser was successful:
when the complete pattern has been mached this value will be set to `true`,
if the complete pattern did not match the subject the value will be `false`.

In addition to the `ok` field, the `matchMax` field indicates the maximum
offset into the subject the parser was able to match the string. If the
matching succeeded `matchMax` equals the total length of the subject, if the
matching failed, the value of `matchMax` is usually a good indication of where
in the subject string the error occurred.

When, during matching, the parser reaches an `E"message"` atom in the grammar,
NPeg will raise an `NPegException` exception with the given message. The typical
use case for this atom is to be combine with the ordered choice `|` operator to
generate helpful error messages. The following example illustrates this:

```nim
let parser = peg "list":
  list <- word * *(comma * word) * eof
  eof <- !1
  comma <- ','
  word <- +{'a'..'z'} | E"word"

echo parser.match("one,two,three,")
```

The rule `word` looks for a sequence of one or more letters (`+{'a'..'z'}`). If
can this not be matched the `E"word"` matches instead, raising an exception:

```
Error: unhandled exception: Parsing error at #14: expected "word" [NPegException]
```

### Left recursion

NPeg does not support left recursion (this applies to PEGs in general). For
example, the rule

```nim
A <- A / 'a'
```

will cause an infinite loop because it allows for left-recursion of the
non-terminal `A`.

Similarly, the grammar

```nim
A <- B / 'a' A
B <- A
```

is problematic because it is mutually left-recursive through the non-terminal
`B`.

Not that loops of patterns that can match the empty string will not result in
the expected behaviour. For example, the rule `*0` will cause the parser to
stall and go into an infinite loop.


## Tracing and debugging

When compiled with `-d:npegTrace`, NPeg will dump its immediate representation
of the compiled PEG, and will dump a trace of the execution during matching.
These traces can be used for debugging or optimization of a grammar.

For example, the following program:

```nim
let parser = peg "line":
  space <- ' '
  line <- word * *(space * word)
  word <- +{'a'..'z'}

discard parser.match("one two")
```

will output the following intermediate representation at compile time.  From
the IR it can be seen that the `space` rule has been inlined in the `line`
rule, but that the `word` rule has been emitted as a subroutine which gets
called from `line`:

```
line:
   0: line           opCall word:6
   1: line           opChoice 5
   2:  space         opStr " "
   3: line           opCall word:6
   4: line           opPartCommit 2
   5:                opReturn

word:
   6: word           opSet '{'a'-'z'}'
   7: word           opSpan '{'a'-'z'}'
   8:                opReturn
```

At runtime, the following trace is generated. The trace consists of a number
of columns:

1. the current instruction pointer, which maps to the compile time dump
2. the index into the subject
3. the substring of the subject
4. the name of the rule from which this instruction originated
5. the instruction being executed
6. the backtrace stack depth

```
  0|  0|one two                 |line           |call -> word:6                |
  6|  0|one two                 |word           |set {'a'-'z'}                 |
  7|  1|ne two                  |word           |span {'a'-'z'}                |
  8|  3| two                    |               |return                        |
  1|  3| two                    |line           |choice -> 5                   |
  2|  3| two                    | space         |str " "                       |*
  3|  4|two                     |line           |call -> word:6                |*
  6|  4|two                     |word           |set {'a'-'z'}                 |*
  7|  5|wo                      |word           |span {'a'-'z'}                |*
  8|  7|                        |               |return                        |*
  4|  7|                        |line           |pcommit -> 2                  |*
  2|  7|                        | space         |str " "                       |*
   |  7|                        |               |fail                          |*
  5|  7|                        |               |return                        |
  5|  7|                        |               |done                          |
```

The exact meaning of the IR instructions is not discussed here.


## Examples

### Parsing mathematical expressions

```nim
let parser = peg "line":
  exp      <- term   * *( ('+'|'-') * term)
  term     <- factor * *( ('*'|'/') * factor)
  factor   <- +{'0'..'9'} | ('(' * exp * ')')
  line     <- exp * !1

doAssert parser.match("3*(4+15)+2").ok
```


### A complete Json parser

The following PEG defines a complete parser for the Json language - it will not produce
any captures, but simple traverse and validate the document:

```nim
let parser = peg "DOC":
  S              <- *{' ','\t','\r','\n'}
  True           <- "true"
  False          <- "false"
  Null           <- "null"

  UnicodeEscape  <- 'u' * {'0'..'9','A'..'F','a'..'f'}{4}
  Escape         <- '\\' * ({ '{', '"', '|', '\\', 'b', 'f', 'n', 'r', 't' } | UnicodeEscape)
  StringBody     <- ?Escape * *( +( {'\x20'..'\xff'} - {'"'} - {'\\'}) * *Escape)
  String         <- ?S * '"' * StringBody * '"' * ?S

  Minus          <- '-'
  IntPart        <- '0' | {'1'..'9'} * *{'0'..'9'}
  FractPart      <- "." * +{'0'..'9'}
  ExpPart        <- ( 'e' | 'E' ) * ?( '+' | '-' ) * +{'0'..'9'}
  Number         <- ?Minus * IntPart * ?FractPart * ?ExpPart

  DOC            <- Json * !1
  Json           <- ?S * ( Number | Object | Array | String | True | False | Null ) * ?S
  Object         <- '{' * ( String * ":" * Json * *( "," * String * ":" * Json ) | ?S ) * "}"
  Array          <- "[" * ( Json * *( "," * Json ) | ?S ) * "]"

let doc = """ {"jsonrpc": "2.0", "method": "subtract", "params": [42, 23], "id": 1} """
doAssert parser.match(doc).ok
```


### Captures

The following example shows how to use code block captures. The defined
grammar will parse a HTTP response document and extract structured data from
the document into a Nim object:

```nim

# Example HTTP response data

const data = """
HTTP/1.1 301 Moved Permanently
Content-Length: 162
Content-Type: text/html
Location: https://nim.org/
"""

# Nim object in which the parsed data will be copied

type
  Request = object
    proto: string
    version: string
    code: int
    message: string
    headers: Table[string, string]

var req: Request
req.headers = initTable[string, string]()

# HTTP grammar (simplified)

let parser = peg "http":
  space       <- ' '
  crlf        <- '\n' * ?'\r'
  alpha       <- {'a'..'z','A'..'Z'}
  digit       <- {'0'..'9'}
  url         <- +(alpha | digit | '/' | '_' | '.')
  eof         <- !1
  header_name <- +(alpha | '-')
  header_val  <- +(1-{'\n'}-{'\r'})
  proto       <- >+alpha:
    req.proto = c[0]
  version     <- >(+digit * '.' * +digit):
    req.version = c[0]
  code        <- >+digit:
    req.code = c[0].parseInt
  msg         <- >(+(1 - '\r' - '\n')):
    req.message = c[0]
  header      <- >header_name * ": " * >header_val:
    req.headers[c[0]] = c[1]
  response    <- proto * '/' * version * space * code * space * msg
  headers     <- *(header * crlf)
  http        <- response * crlf * headers * eof


# Parse the data and print the resulting table

let res = parser.match(data)
echo req
```

The resulting data:

```nim
(
  proto: "HTTP",
  version: "1.1",
  code: 301,
  message: "Moved Permanently",
  headers: {
    "Content-Length": "162",
    "Content-Type":
    "text/html",
    "Location": "https://nim.org/"
  }
)
```

