///|
/// Classify a parsed JSON-RPC message. A `method` wins over a colliding `id`,
/// which is required for server-to-client requests.
pub fn classify_message(payload : String) -> MessageKind raise ProtocolError {
  let object = parse_object(payload)
  match object.get("method") {
    Some(String(method_name)) =>
      match object.get("id") {
        None | Some(Null) => Notification(method_name)
        Some(id) => ServerRequest(parse_request_id(id), method_name)
      }
    Some(_) => raise InvalidMessage(reason="method must be a string")
    None =>
      match object.get("id") {
        Some(id) => Response(parse_request_id(id))
        None => raise InvalidMessage(reason="message has neither method nor id")
      }
  }
}

///|
/// Build the initialize request with capabilities needed by a diagnostics-only
/// test client.
pub fn encode_initialize(
  id : RequestId,
  root_uri : String,
  root_path : String,
  client_process_id : Int,
) -> String {
  Json::object({
    "jsonrpc": Json::string("2.0"),
    "id": request_id_json(id),
    "method": Json::string("initialize"),
    "params": Json::object({
      "processId": Json::number(client_process_id.to_double()),
      // Keep the deprecated field for servers that have not completely
      // migrated their workspace discovery from rootPath to rootUri.
      "rootPath": Json::string(root_path),
      "rootUri": Json::string(root_uri),
      "workspaceFolders": Json::array([
        Json::object({
          "uri": Json::string(root_uri),
          "name": Json::string("moon-lsp-compiletest"),
        }),
      ]),
      "capabilities": Json::object({
        "general": Json::object({
          "positionEncodings": Json::array([Json::string("utf-16")]),
        }),
        "workspace": Json::object({
          "configuration": Json::boolean(true),
          "didChangeWatchedFiles": Json::object({
            "dynamicRegistration": Json::boolean(true),
          }),
          "workspaceFolders": Json::boolean(true),
        }),
        "textDocument": Json::object({
          "publishDiagnostics": Json::object({
            "relatedInformation": Json::boolean(true),
          }),
          "synchronization": Json::object({
            "didSave": Json::boolean(false),
            "willSave": Json::boolean(false),
            "willSaveWaitUntil": Json::boolean(false),
          }),
        }),
      }),
    }),
  }).stringify()
}

///|
pub fn encode_initialized() -> String {
  notification("initialized", Json::empty_object())
}

///|
pub fn encode_did_open(uri : String, version : Int, text : String) -> String {
  notification(
    "textDocument/didOpen",
    Json::object({
      "textDocument": Json::object({
        "uri": Json::string(uri),
        "languageId": Json::string("moonbit"),
        "version": Json::number(version.to_double()),
        "text": Json::string(text),
      }),
    }),
  )
}

///|
/// Send a complete replacement. LSP permits this form even when a server
/// advertises incremental synchronization, and it avoids coupling a
/// diagnostics regression tool to an editor's individual keystroke ranges.
pub fn encode_did_change(
  uri : String,
  version : Int,
  old_text : String,
  new_text : String,
) -> String {
  let _ = old_text
  notification(
    "textDocument/didChange",
    Json::object({
      "textDocument": Json::object({
        "uri": Json::string(uri),
        "version": Json::number(version.to_double()),
      }),
      "contentChanges": Json::array([
        Json::object({ "text": Json::string(new_text) }),
      ]),
    }),
  )
}

///|
pub fn encode_did_close(uri : String) -> String {
  notification(
    "textDocument/didClose",
    Json::object({ "textDocument": Json::object({ "uri": Json::string(uri) }) }),
  )
}

///|
pub fn encode_did_save(uri : String, text : String) -> String {
  notification(
    "textDocument/didSave",
    Json::object({
      "textDocument": Json::object({ "uri": Json::string(uri) }),
      "text": Json::string(text),
    }),
  )
}

///|
/// Notify a workspace-oriented server that the on-disk copy of an already
/// open document changed. The in-memory edit remains authoritative; this
/// notification only makes the isolated test workspace observable to servers
/// that schedule analysis through file watching.
pub fn encode_watched_file_changed(uri : String) -> String {
  notification(
    "workspace/didChangeWatchedFiles",
    Json::object({
      "changes": Json::array([
        Json::object({ "uri": Json::string(uri), "type": Json::number(2.0) }),
      ]),
    }),
  )
}

///|
/// `moon-lsp` rejects an explicit `params: null` for shutdown; omit params.
pub fn encode_shutdown(id : RequestId) -> String {
  Json::object({
    "jsonrpc": Json::string("2.0"),
    "id": request_id_json(id),
    "method": Json::string("shutdown"),
  }).stringify()
}

///|
pub fn encode_exit() -> String {
  Json::object({
    "jsonrpc": Json::string("2.0"),
    "method": Json::string("exit"),
  }).stringify()
}

///|
pub fn encode_null_response(id : RequestId) -> String {
  Json::object({
    "jsonrpc": Json::string("2.0"),
    "id": request_id_json(id),
    "result": Json::null(),
  }).stringify()
}

///|
/// Decode only `textDocument/publishDiagnostics`; other JSON-RPC messages are
/// deliberately ignored by returning `None`.
pub fn decode_publish_diagnostics(
  payload : String,
) -> @model.DiagnosticSnapshot? raise ProtocolError {
  let object = parse_object(payload)
  match object.get("method") {
    Some(String("textDocument/publishDiagnostics")) => {
      let params = required_object(
        object, "params", "publishDiagnostics params",
      )
      let uri = required_string(params, "uri", "diagnostic uri")
      let version = optional_int(params, "version", "diagnostic version")
      let diagnostics = required_array(params, "diagnostics", "diagnostics")
      let decoded = []
      for diagnostic in diagnostics {
        decoded.push(decode_diagnostic(diagnostic))
      }
      Some({ uri, version, diagnostics: decoded, unversioned: version is None })
    }
    _ => None
  }
}

///|
/// Verify that an initialize response advertises incremental text sync. LSP
/// permits either a numeric `textDocumentSync: 2` or an object with `change: 2`.
pub fn ensure_incremental_sync(payload : String) -> Unit raise ProtocolError {
  let result = required_object(
    parse_object(payload),
    "result",
    "initialize result",
  )
  match result.get("capabilities") {
    Some(Object(capabilities)) =>
      match capabilities.get("textDocumentSync") {
        Some(Number(number, ..)) if number == 2.0 => ()
        Some(Object(sync)) =>
          match sync.get("change") {
            Some(Number(number, ..)) if number == 2.0 => ()
            _ =>
              raise UnsupportedCapability(
                reason="textDocumentSync.change must be incremental (2)",
              )
          }
        _ =>
          raise UnsupportedCapability(
            reason="server does not advertise incremental textDocumentSync",
          )
      }
    _ =>
      raise UnsupportedCapability(
        reason="initialize result has no capabilities object",
      )
  }
}

///|
/// Convert an absolute POSIX path to a file URI, preserving RFC 3986 path
/// characters and escaping raw `%`, whitespace, `#`, `?`, and non-ASCII UTF-8
/// bytes.
pub fn path_to_file_uri(path : String) -> String raise ProtocolError {
  if !path.has_prefix("/") {
    raise InvalidFileUri(reason="path must be an absolute POSIX path")
  }
  if path.contains_code_unit(0) {
    raise InvalidFileUri(reason="path contains NUL")
  }
  let encoded = StringBuilder(size_hint=path.length() + 8)
  for byte in @utf8.encode(path) {
    if uri_path_byte_allowed(byte) {
      encoded.write_char(byte.to_char())
    } else {
      encoded.write_string("%")
      encoded.write_string(hex_byte(byte))
    }
  }
  "file://\{encoded.to_string()}"
}

///|
fn parse_object(payload : String) -> Map[String, Json] raise ProtocolError {
  let json = @json.parse(payload) catch {
    _ => raise InvalidJson(reason="payload is not valid JSON")
  }
  match json {
    Object(object) => object
    _ => raise InvalidMessage(reason="JSON-RPC payload must be an object")
  }
}

///|
fn parse_request_id(value : Json) -> RequestId raise ProtocolError {
  match value {
    String(text) => Text(text)
    Number(number, ..) => {
      let integer = number.to_int()
      if integer.to_double() != number {
        raise InvalidMessage(reason="request id number must be an integer")
      }
      Number(integer)
    }
    _ => raise InvalidMessage(reason="request id must be a string or number")
  }
}

///|
fn request_id_json(id : RequestId) -> Json {
  match id {
    Number(number) => Json::number(number.to_double())
    Text(text) => Json::string(text)
  }
}

///|
fn notification(method_name : String, params : Json) -> String {
  Json::object({
    "jsonrpc": Json::string("2.0"),
    "method": Json::string(method_name),
    "params": params,
  }).stringify()
}

///|
fn decode_diagnostic(value : Json) -> @model.Diagnostic raise ProtocolError {
  let object = json_object(value, "diagnostic")
  let range = decode_range(required_value(object, "range", "diagnostic range"))
  let severity = optional_severity(object)
  let code = optional_code(object)
  let source = optional_string(object, "source", "diagnostic source")
  let message = required_string(object, "message", "diagnostic message")
  { range, severity, code, source, message }
}

///|
fn decode_range(value : Json) -> @model.Range raise ProtocolError {
  let object = json_object(value, "range")
  let start = decode_position(required_value(object, "start", "range start"))
  let end = decode_position(required_value(object, "end", "range end"))
  if end.line < start.line ||
    (end.line == start.line && end.character < start.character) {
    raise InvalidDiagnostic(reason="range end precedes range start")
  }
  { start, end }
}

///|
fn decode_position(value : Json) -> @model.Position raise ProtocolError {
  let object = json_object(value, "position")
  let line = required_int(object, "line", "position line")
  let character = required_int(object, "character", "position character")
  if line < 0 || character < 0 {
    raise InvalidDiagnostic(reason="position values must be non-negative")
  }
  { line, character }
}

///|
fn optional_severity(
  object : Map[String, Json],
) -> @model.Severity? raise ProtocolError {
  match object.get("severity") {
    None | Some(Null) => None
    Some(Number(number, ..)) =>
      match number.to_int() {
        1 if number == 1.0 => Some(Error)
        2 if number == 2.0 => Some(Warning)
        3 if number == 3.0 => Some(Information)
        4 if number == 4.0 => Some(Hint)
        _ => raise InvalidDiagnostic(reason="unsupported diagnostic severity")
      }
    Some(_) =>
      raise InvalidDiagnostic(reason="diagnostic severity must be a number")
  }
}

///|
fn optional_code(
  object : Map[String, Json],
) -> @model.DiagnosticCode? raise ProtocolError {
  match object.get("code") {
    None | Some(Null) => None
    Some(String(code)) => Some(Text(code))
    Some(Number(number, ..)) => {
      let integer = number.to_int()
      if integer.to_double() != number {
        raise InvalidDiagnostic(
          reason="diagnostic code number must be an integer",
        )
      }
      Some(Number(integer))
    }
    Some(_) =>
      raise InvalidDiagnostic(reason="diagnostic code must be string or number")
  }
}

///|
fn required_object(
  object : Map[String, Json],
  key : String,
  context : String,
) -> Map[String, Json] raise ProtocolError {
  json_object(required_value(object, key, context), context)
}

///|
fn required_array(
  object : Map[String, Json],
  key : String,
  context : String,
) -> Array[Json] raise ProtocolError {
  match required_value(object, key, context) {
    Array(values) => values
    _ => raise InvalidDiagnostic(reason="\{context} must be an array")
  }
}

///|
fn json_object(
  value : Json,
  context : String,
) -> Map[String, Json] raise ProtocolError {
  match value {
    Object(object) => object
    _ => raise InvalidDiagnostic(reason="\{context} must be an object")
  }
}

///|
fn required_value(
  object : Map[String, Json],
  key : String,
  context : String,
) -> Json raise ProtocolError {
  match object.get(key) {
    Some(value) => value
    None => raise InvalidDiagnostic(reason="missing \{context}")
  }
}

///|
fn required_string(
  object : Map[String, Json],
  key : String,
  context : String,
) -> String raise ProtocolError {
  match required_value(object, key, context) {
    String(value) => value
    _ => raise InvalidDiagnostic(reason="\{context} must be a string")
  }
}

///|
fn optional_string(
  object : Map[String, Json],
  key : String,
  context : String,
) -> String? raise ProtocolError {
  match object.get(key) {
    None | Some(Null) => None
    Some(String(value)) => Some(value)
    Some(_) => raise InvalidDiagnostic(reason="\{context} must be a string")
  }
}

///|
fn optional_int(
  object : Map[String, Json],
  key : String,
  context : String,
) -> Int? raise ProtocolError {
  match object.get(key) {
    None | Some(Null) => None
    Some(value) => Some(json_int(value, context))
  }
}

///|
fn required_int(
  object : Map[String, Json],
  key : String,
  context : String,
) -> Int raise ProtocolError {
  json_int(required_value(object, key, context), context)
}

///|
fn json_int(value : Json, context : String) -> Int raise ProtocolError {
  match value {
    Number(number, ..) => {
      let integer = number.to_int()
      if integer.to_double() != number {
        raise InvalidDiagnostic(reason="\{context} must be an integer")
      }
      integer
    }
    _ => raise InvalidDiagnostic(reason="\{context} must be a number")
  }
}

///|
fn uri_path_byte_allowed(byte : Byte) -> Bool {
  (byte >= b'a' && byte <= b'z') ||
  (byte >= b'A' && byte <= b'Z') ||
  (byte >= b'0' && byte <= b'9') ||
  byte == b'-' ||
  byte == b'.' ||
  byte == b'_' ||
  byte == b'~' ||
  byte == b'!' ||
  byte == b'$' ||
  byte == b'&' ||
  byte == b'\'' ||
  byte == b'(' ||
  byte == b')' ||
  byte == b'*' ||
  byte == b'+' ||
  byte == b',' ||
  byte == b';' ||
  byte == b'=' ||
  byte == b':' ||
  byte == b'@' ||
  byte == b'/'
}

///|
fn hex_byte(byte : Byte) -> String {
  let table = "0123456789ABCDEF"
  let value = byte.to_int()
  let high = table.get_char(value / 16).unwrap()
  let low = table.get_char(value % 16).unwrap()
  String::from_array([high, low])
}
