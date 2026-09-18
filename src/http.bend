import Base

# Http
# ====
#
# Small, pure HTTP/1.1 helpers: parsing a request line and building a
# response. Nothing here touches a socket -- that split is what lets
# LAWS.bend state facts about parsing and formatting without any IO.

type Request is Data:
  Request{method: String, path: String}

# The request line is the first line of the raw request text, e.g.
# "GET /compute/20 HTTP/1.1". `String.lines` splits on '\n'; the '\r'
# that precedes it (if any) is harmless, since we only compare/consume
# from the front of the line.
def request_line(raw: String) -> String:
  Maybe.default(&2, String, List.head(&2, String, String.lines(raw)), "")

def tokens_of(line: String) -> List<&2, String>:
  List.filter(~String, ~(s => Bool.not(String.is_empty(s))),
    String.split(line, ' '))

def token(xs: List<&2, String>, n: Nat) -> String:
  Maybe.default(&2, String, List.get(&2, String, xs, n), "")

# Parses "METHOD PATH VERSION..." into a Request. A malformed or empty
# line becomes Request{"", ""}, which matches no route and falls through
# to 404 -- there is no way for a bad request line to crash the server.
def parse_request(raw: String) -> Request:
  +ts = tokens_of(request_line(raw))
  Request{token(ts, 0n), token(ts, 1n)}

# Drops `prefix` from the front of `s`, if it is there.
def strip_prefix.if(s: String, prefix: String, ok: Bool) -> Maybe<&2, String>:
  match ok:
    case True{}:
      Some{String.drop(s, String.length(prefix))}
    case False{}:
      None{}

def strip_prefix(+s: String, +prefix: String) -> Maybe<&2, String>:
  strip_prefix.if(s, prefix, String.starts_with(s, prefix))

def status_text.d500(code: Nat) -> String:
  "Internal Server Error"

def status_text.d404(+code: Nat, hit: Bool) -> String:
  match hit:
    case True{}:
      "Not Found"
    case False{}:
      status_text.d500(code)

def status_text.d400(+code: Nat, hit: Bool) -> String:
  match hit:
    case True{}:
      "Bad Request"
    case False{}:
      status_text.d404(code, Nat.is_eq(code, 404n))

def status_text.c200(+code: Nat, hit: Bool) -> String:
  match hit:
    case True{}:
      "OK"
    case False{}:
      status_text.d400(code, Nat.is_eq(code, 400n))

def status_text(+code: Nat) -> String:
  status_text.c200(code, Nat.is_eq(code, 200n))

# A complete HTTP/1.1 response: status line, three headers, blank line,
# body. `Connection: close` keeps the protocol subset small (one
# request per connection), so there is no keep-alive state to get wrong.
def response(+code: Nat, ctype: String, +body: String) -> String:
  status = status_text(code)
  header = String.concat([
    "HTTP/1.1 ", Nat.show(code), " ", status, "\r\n",
    "Content-Type: ", ctype, "\r\n",
    "Content-Length: ", Nat.show(String.length(body)), "\r\n",
    "Connection: close\r\n",
    "\r\n"])
  String.append(header, body)

def text_response(code: Nat, body: String) -> String:
  response(code, "text/plain; charset=utf-8", body)

def not_found() -> String:
  text_response(404n, "404 Not Found\n")

def bad_request(msg: String) -> String:
  text_response(400n, String.append(msg, "\n"))
