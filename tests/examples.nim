import unittest
import npeg
import json
import strutils
import tables

{.push warning[Spacing]: off.}


suite "examples":

  ######################################################################

  test "misc":

    let p1 = patt +{'a'..'z'}
    doAssert p1.match("lowercaseword").ok

    let p2 = peg "ident":
      lower <- {'a'..'z'}
      ident <- +lower
    doAssert p2.match("lowercaseword").ok

  ######################################################################

  test "matchFile":

    let parser = peg "pairs":
      pairs <- pair * *(',' * pair)
      word <- +{'a'..'z'}
      number <- +{'0'..'9'}
      pair <- (>word * '=' * >number)

    let r = parser.matchFile "tests/testdata"
    doAssert r.ok
    doAssert r.captures == @["one", "1", "two", "2", "three", "3", "four", "4"]

  ######################################################################

  test "expression parser":

    let s = peg "line":
      ws       <- *' '
      number   <- +Digit * ws
      termOp   <- {'+', '-'} * ws
      factorOp <- {'*', '/'} * ws
      open     <- '(' * ws
      close    <- ')' * ws
      eol      <- !1
      exp      <- term * *(termOp * term)
      term     <- factor * *(factorOp * factor)
      factor   <- number | (open * exp * close)
      line     <- ws * exp * eol

    doAssert s.match("1").ok
    doAssert s.match("1+1").ok
    doAssert s.match("1+1*1").ok
    doAssert s.match("(1+1)*1").ok
    doAssert s.match("13 + 5 * (2+1)").ok

  ######################################################################

  test "JSON parser":

    let json = """
      {
          "glossary": {
              "title": "example glossary",
              "GlossDiv": {
                  "title": "S",
                  "GlossList": {
                      "GlossEntry": {
                          "ID": "SGML",
                              "SortAs": "SGML",
                              "GlossTerm": "Standard Generalized Markup Language",
                              "Acronym": "SGML",
                              "Abbrev": "ISO 8879:1986",
                              "GlossDef": {
                              "para": "A meta-markup language, used to create markup languages such as DocBook.",
                              "GlossSeeAlso": ["GML", "XML"]
                          },
                          "GlossSee": "markup"
                      }
                  }
              }
          }
      }
      """

    let s = peg "DOC":
      S              <- *Space
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

      DOC            <- JSON * !1
      JSON           <- ?S * ( Number | Object | Array | String | True | False | Null ) * ?S
      Object         <- '{' * ( String * ":" * JSON * *( "," * String * ":" * JSON ) | ?S ) * "}"
      Array          <- "[" * ( JSON * *( "," * JSON ) | ?S ) * "]"

    doAssert s.match(json).ok

  ######################################################################

  test "HTTP with action captures to Nim object":

    type
      Request = object
        proto: string
        version: string
        code: int
        message: string
        headers: Table[string, string]

    var req: Request
    req.headers = initTable[string, string]()

    let s = peg "http":
      space       <- ' '
      crlf        <- '\n' * ?'\r'
      url         <- +(Alpha | Digit | '/' | '_' | '.')
      eof         <- !1
      header_name <- +(Alpha | '-')
      header_val  <- +(1-{'\n'}-{'\r'})
      proto       <- >(+Alpha) % (req.proto = c[0])
      version     <- >(+Digit * '.' * +Digit) % (req.version = c[0])
      code        <- >(+Digit) % (req.code = c[0].parseInt)
      msg         <- >(+(1 - '\r' - '\n')) % (req.message = c[0])
      header      <- (>header_name * ": " * >header_val) % (req.headers[c[0]] = c[1])

      response    <- proto * '/' * version * space * code * space * msg 
      headers     <- *(header * crlf)
      http        <- response * crlf * headers * eof

    let data = """
HTTP/1.1 301 Moved Permanently
Content-Length: 162
Content-Type: text/html
Location: https://nim.org/
"""

    let res = s.match(data)
    doAssert res.ok
    doAssert req.proto == "HTTP"
    doAssert req.version == "1.1"
    doAssert req.code == 301
    doAssert req.message == "Moved Permanently"
    doAssert req.headers["Content-Length"] == "162"
    doAssert req.headers["Content-Type"] == "text/html"
    doAssert req.headers["Location"] == "https://nim.org/"

  ######################################################################

  test "HTTP capture to Json":
    let s = peg "http":
      space       <- ' '
      crlf        <- '\n' * ?'\r'
      url         <- +(Alpha | Digit | '/' | '_' | '.')
      eof         <- !1
      header_name <- +(Alpha | '-')
      header_val  <- +(1-{'\n'}-{'\r'})
      proto       <- Jf("proto", Js(+Alpha) )
      version     <- Jf("version", Js(+Digit * '.' * +Digit) )
      code        <- Jf("code", Ji(+Digit) )
      msg         <- Jf("msg", Js(+(1 - '\r' - '\n')) )
      header      <- Ja( Js(header_name) * ": " * Js(header_val) )

      response    <- Jf("response", Jo( proto * '/' * version * space * code * space * msg ))
      headers     <- Jf("headers", Ja( *(header * crlf) ))
      http        <- Jo(response * crlf * headers * eof)

    let data = """
HTTP/1.1 301 Moved Permanently
Content-Length: 162
Content-Type: text/html
Location: https://nim.org/
"""

    let res = s.match(data)
    doAssert res.ok
    doAssert res.capturesJson == parseJson("""{"response":{"proto":"HTTP","version":"1.1","code":301,"msg":"Moved Permanently"},"headers":[["Content-Length","162"],["Content-Type","text/html"],["Location","https://nim.org/"]]}""")

  ######################################################################

  test "UTF-8":

    let b = "  añyóng  ♜♞♝♛♚♝♞♜ оживлённым   "

    let m = peg "s":

      cont <- {128..191}

      utf8 <- {0..127} |
              {194..223} * cont{1} |
              {224..239} * cont{2} |
              {240..244} * cont{3}

      s <- *(@ > +(utf8-' '))

    let r = m.match(b)
    doAssert r.ok
    let c = r.captures
    doAssert c[0] == "añyóng"
    doAssert c[1] == "♜♞♝♛♚♝♞♜"
    doAssert c[2] == "оживлённым"

