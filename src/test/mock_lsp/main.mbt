///|
/// Deterministic native stdio LSP double used by the session integration
/// tests.  It intentionally understands only the small JSON-RPC lifecycle
/// exercised by this repository; it is not a general-purpose fake server.
enum Scenario {
  Normal
  MultiUri
  StderrFlood
  PartialFrame
  EarlyExit
  Timeout
  IdCollision
} derive(Debug, Eq)

///|
fn scenario_name(scenario : Scenario) -> String {
  match scenario {
    Normal => "normal"
    MultiUri => "multi-uri"
    StderrFlood => "stderr-flood"
    PartialFrame => "partial-frame"
    EarlyExit => "early-exit"
    Timeout => "timeout"
    IdCollision => "id-collision"
  }
}

///|
fn parse_scenario(value : String) -> Scenario? {
  match value.trim() {
    "normal" => Some(Normal)
    "multi-uri" => Some(MultiUri)
    "stderr-flood" => Some(StderrFlood)
    "partial-frame" => Some(PartialFrame)
    "early-exit" => Some(EarlyExit)
    "timeout" => Some(Timeout)
    "id-collision" => Some(IdCollision)
    _ => None
  }
}

///|
async fn scenario_from_working_directory() -> Scenario? {
  let path = ".moon-lsp-compiletest-mock-scenario"
  let file = @fs.open(path, mode=ReadOnly) catch { _ => return Some(Normal) }
  defer file.close()
  let size = file.size() catch { _ => return None }
  if size < 0L || size > 128L {
    return None
  }
  let bytes = file.read_exactly(size.to_int()) catch { _ => return None }
  let value = @utf8.decode(bytes) catch { _ => return None }
  parse_scenario(value)
}

///|
async fn parse_cli_scenario(args : Array[String]) -> Result[Scenario, String] {
  let stdio_mode = args.length() == 1 ||
    (args.length() == 2 && args[1] == "--stdio") ||
    (
      args.length() == 3 &&
      args[1] == "--stdio" &&
      args[2].has_prefix("--clientProcessId=")
    )
  if stdio_mode {
    match scenario_from_working_directory() {
      Some(scenario) => Ok(scenario)
      None => Err("invalid .moon-lsp-compiletest-mock-scenario value")
    }
  } else if args.length() == 3 && args[1] == "--scenario" {
    match parse_scenario(args[2]) {
      Some(scenario) => Ok(scenario)
      None => Err("unknown scenario: \{args[2]}")
    }
  } else {
    Err(
      "usage: mock_lsp [--stdio] [--scenario normal|multi-uri|stderr-flood|partial-frame|early-exit|timeout|id-collision]",
    )
  }
}

///|
fn request_id_json(id : @protocol.RequestId) -> Json {
  match id {
    Number(number) => Json::number(number.to_double())
    Text(text) => Json::string(text)
  }
}

///|
fn initialize_response(id : @protocol.RequestId) -> String {
  Json::object({
    "jsonrpc": Json::string("2.0"),
    "id": request_id_json(id),
    "result": Json::object({
      "capabilities": Json::object({ "textDocumentSync": Json::number(2.0) }),
    }),
  }).stringify()
}

///|
fn register_capability_request(id : Int) -> String {
  Json::object({
    "jsonrpc": Json::string("2.0"),
    "id": Json::number(id.to_double()),
    "method": Json::string("client/registerCapability"),
    "params": Json::object({ "registrations": Json::array([]) }),
  }).stringify()
}

///|
fn target_diagnostics(uri : String, clear~ : Bool) -> String {
  let diagnostics = if clear {
    Json::array([])
  } else {
    Json::array([
      Json::object({
        "range": Json::object({
          "start": Json::object({
            "line": Json::number(0.0),
            "character": Json::number(0.0),
          }),
          "end": Json::object({
            "line": Json::number(0.0),
            "character": Json::number(1.0),
          }),
        }),
        "severity": Json::number(1.0),
        "code": Json::string("E4021"),
        "source": Json::string("mock-lsp"),
        "message": Json::string("mock unresolved name"),
      }),
    ])
  }
  Json::object({
    "jsonrpc": Json::string("2.0"),
    "method": Json::string("textDocument/publishDiagnostics"),
    "params": Json::object({
      "uri": Json::string(uri),
      // Deliberately unversioned: current moon-lsp may omit the version too.
      "diagnostics": diagnostics,
    }),
  }).stringify()
}

///|
fn other_uri(uri : String) -> String {
  if uri.has_suffix(".mbt") {
    uri[:uri.length() - 4].to_owned() + "-other.mbt"
  } else {
    uri + ".other"
  }
}

///|
async fn write_frame(payload : String) -> Unit {
  @stdio.stdout.write(@framing.encode_frame(payload))
}

///|
async fn write_partial_frame(payload : String) -> Unit {
  let byte_length = @utf8.encode(payload).length()
  let header = "Content-Length: \{byte_length}\r\n\r\n"
  // The payload produced by this fixture is ASCII-only, hence this prefix is
  // also a valid byte prefix.  Leaving it unfinished is the behavior under
  // test, not an encoding accident.
  let prefix_length = payload.length() / 2
  @stdio.stdout.write(header)
  @stdio.stdout.write(payload[:prefix_length])
}

///|
async fn write_stderr_flood() -> Unit {
  let line = "mock-lsp stderr flood: " + "x".repeat(1000) + "\n"
  for _ in 0..<64 {
    @stdio.stderr.write(line)
  }
}

///|
fn json_object(payload : String) -> Map[String, Json]? {
  let json = @json.parse(payload) catch { _ => return None }
  match json {
    Object(object) => Some(object)
    _ => None
  }
}

///|
fn message_uri(payload : String) -> String? {
  match json_object(payload) {
    Some(root) =>
      match root.get("params") {
        Some(Object(params)) =>
          match params.get("textDocument") {
            Some(Object(document)) =>
              match document.get("uri") {
                Some(String(uri)) => Some(uri)
                _ => None
              }
            _ => None
          }
        _ => None
      }
    None => None
  }
}

///|
fn change_version(payload : String) -> Int? {
  match json_object(payload) {
    Some(root) =>
      match root.get("params") {
        Some(Object(params)) =>
          match params.get("textDocument") {
            Some(Object(document)) =>
              match document.get("version") {
                Some(Number(version, ..)) => {
                  let integer = version.to_int()
                  if integer.to_double() == version {
                    Some(integer)
                  } else {
                    None
                  }
                }
                _ => None
              }
            _ => None
          }
        _ => None
      }
    None => None
  }
}

///|
async fn send_initialize_messages(
  scenario : Scenario,
  initialize_id : @protocol.RequestId,
) -> Unit {
  let registration_id = match scenario {
    IdCollision => 1
    _ => 99
  }
  // Send the request first, intentionally exercising the rule that a method
  // takes precedence over a matching numeric id when a client awaits init.
  write_frame(register_capability_request(registration_id))
  write_frame(initialize_response(initialize_id))
  if scenario == StderrFlood {
    write_stderr_flood()
  }
}

///|
async fn handle_change(
  scenario : Scenario,
  uri : String,
  version : Int,
) -> Bool {
  if scenario == Timeout {
    // Stay alive and consume lifecycle traffic; the caller's diagnostic wait
    // must expire rather than receiving a synthetic response.
    return true
  }
  if version == 2 {
    if scenario == MultiUri {
      write_frame(target_diagnostics(other_uri(uri), clear=false))
    }
    let target = target_diagnostics(uri, clear=false)
    if scenario == PartialFrame {
      write_partial_frame(target)
      return false
    }
    write_frame(target)
  } else if version >= 3 {
    if scenario == MultiUri {
      write_frame(target_diagnostics(other_uri(uri), clear=true))
    }
    write_frame(target_diagnostics(uri, clear=true))
  }
  true
}

///|
async fn run_mock(scenario : Scenario) -> Int {
  if scenario == EarlyExit {
    @stdio.stderr.write(
      "mock-lsp: early-exit scenario (\{scenario_name(scenario)})\n",
    )
    return 0
  }

  let decoder = @framing.FrameDecoder::new(max_content_length=1_048_576)
  let current_uri = Ref("file:///mock.mbt")
  let initialized = Ref(false)
  let keep_running = Ref(true)
  while keep_running.val {
    match @stdio.stdin.read_some(max_len=4096) {
      None => keep_running.val = false
      Some(chunk) => {
        let payloads = decoder.feed(chunk) catch {
          _ => {
            @stdio.stderr.write("mock-lsp: invalid client frame\n")
            keep_running.val = false
            []
          }
        }
        for payload in payloads {
          if keep_running.val {
            let kind = @protocol.classify_message(payload) catch {
              _ => {
                @stdio.stderr.write("mock-lsp: invalid client message\n")
                continue
              }
            }
            match kind {
              ServerRequest(id, "initialize") =>
                if !initialized.val {
                  initialized.val = true
                  send_initialize_messages(scenario, id)
                }
              ServerRequest(id, "shutdown") =>
                write_frame(@protocol.encode_null_response(id))
              ServerRequest(id, _) =>
                write_frame(@protocol.encode_null_response(id))
              Notification("textDocument/didOpen") =>
                match message_uri(payload) {
                  Some(uri) => current_uri.val = uri
                  None => ()
                }
              Notification("textDocument/didChange") => {
                let uri = match message_uri(payload) {
                  Some(uri) => uri
                  None => current_uri.val
                }
                let version = match change_version(payload) {
                  Some(version) => version
                  None => 0
                }
                keep_running.val = handle_change(scenario, uri, version)
              }
              Notification("exit") => keep_running.val = false
              Notification(_) | Response(_) => ()
            }
          }
        }
      }
    }
  }
  0
}

///|
async fn main {
  let code = match parse_cli_scenario(@env.args()) {
    Ok(scenario) => run_mock(scenario)
    Err(message) => {
      @stdio.stderr.write("mock-lsp: \{message}\n")
      64
    }
  }
  if code != 0 {
    abort("mock-lsp exited with status \{code}")
  }
}
