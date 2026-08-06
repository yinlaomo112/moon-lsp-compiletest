///|
test "protocol classifies server requests before colliding ids" {
  assert_eq(
    classify_message(
      "{\"jsonrpc\":\"2.0\",\"id\":7,\"method\":\"client/registerCapability\",\"params\":{}}",
    ),
    ServerRequest(Number(7), "client/registerCapability"),
  )
  assert_eq(
    classify_message("{\"jsonrpc\":\"2.0\",\"method\":\"$/progress\"}"),
    Notification("$/progress"),
  )
  assert_eq(
    classify_message("{\"jsonrpc\":\"2.0\",\"id\":\"init\",\"result\":{}}"),
    Response(Text("init")),
  )
}

///|
test "protocol encodes lifecycle messages and complete replacements" {
  let initialize = encode_initialize(
    Number(1),
    "file:///tmp/case",
    "/tmp/case",
    123,
  )
  assert_true(initialize.contains("\"positionEncodings\":[\"utf-16\"]"))
  assert_true(initialize.contains("\"rootUri\":\"file:///tmp/case\""))
  assert_true(initialize.contains("\"rootPath\":\"/tmp/case\""))
  assert_true(initialize.contains("\"processId\":123"))
  assert_true(initialize.contains("\"workspaceFolders\""))
  assert_true(initialize.contains("\"dynamicRegistration\":true"))

  let change = encode_did_change(
    "file:///tmp/case/main.mbt", 3, "a😀", "next",
  )
  assert_true(!change.contains("\"range\""))
  assert_true(change.contains("\"version\":3"))
  assert_true(
    encode_watched_file_changed("file:///tmp/case/main.mbt").contains(
      "\"workspace/didChangeWatchedFiles\"",
    ),
  )

  let shutdown = encode_shutdown(Number(99))
  assert_true(!shutdown.contains("\"params\""))
  assert_true(!encode_exit().contains("\"params\""))
  assert_true(
    encode_null_response(Text("server-7")).contains("\"result\":null"),
  )
}

///|
test "protocol decodes complete publishDiagnostics and ignores other methods" {
  let payload = "{\"jsonrpc\":\"2.0\",\"method\":\"textDocument/publishDiagnostics\",\"params\":{\"uri\":\"file:///tmp/main.mbt\",\"diagnostics\":[{\"range\":{\"start\":{\"line\":1,\"character\":2},\"end\":{\"line\":1,\"character\":4}},\"severity\":1,\"code\":\"E4021\",\"source\":\"moonbit\",\"message\":\"cannot find value\"}]}}"
  let snapshot = decode_publish_diagnostics(payload).unwrap()
  assert_eq(snapshot.uri, "file:///tmp/main.mbt")
  assert_true(snapshot.unversioned)
  assert_eq(snapshot.diagnostics.length(), 1)
  let diagnostic = snapshot.diagnostics[0]
  assert_eq(diagnostic.range.start.line, 1)
  assert_eq(diagnostic.range.end.character, 4)
  assert_true(diagnostic.severity is Some(Error))
  assert_true(diagnostic.code is Some(Text("E4021")))
  assert_eq(diagnostic.source, Some("moonbit"))
  assert_eq(
    decode_publish_diagnostics(
      "{\"jsonrpc\":\"2.0\",\"method\":\"window/logMessage\",\"params\":{}}",
    ),
    None,
  )
}

///|
test "protocol validates incremental sync and POSIX file URI encoding" {
  ensure_incremental_sync(
    "{\"jsonrpc\":\"2.0\",\"id\":1,\"result\":{\"capabilities\":{\"textDocumentSync\":2}}}",
  )
  ensure_incremental_sync(
    "{\"jsonrpc\":\"2.0\",\"id\":1,\"result\":{\"capabilities\":{\"textDocumentSync\":{\"openClose\":true,\"change\":2}}}}",
  )
  let rejected = try
    ensure_incremental_sync(
      "{\"jsonrpc\":\"2.0\",\"id\":1,\"result\":{\"capabilities\":{\"textDocumentSync\":1}}}",
    )
  catch {
    UnsupportedCapability(_) => true
    _ => false
  } noraise {
    _ => false
  }
  assert_true(rejected)
  assert_eq(
    path_to_file_uri("/tmp/a b/中文#x?y%z"),
    "file:///tmp/a%20b/%E4%B8%AD%E6%96%87%23x%3Fy%25z",
  )
}

///|
test "protocol rejects invalid JSON-RPC and malformed diagnostics" {
  let invalid_json = try classify_message("not json") catch {
    InvalidJson(_) => true
    _ => false
  } noraise {
    _ => false
  }
  assert_true(invalid_json)
  let invalid_diagnostic = try
    decode_publish_diagnostics(
      "{\"method\":\"textDocument/publishDiagnostics\",\"params\":{\"uri\":\"file:///x\",\"diagnostics\":[{\"message\":\"missing range\"}]}}",
    )
  catch {
    InvalidDiagnostic(_) => true
    _ => false
  } noraise {
    _ => false
  }
  assert_true(invalid_diagnostic)
  let relative_path = try path_to_file_uri("tmp/not-absolute") catch {
    InvalidFileUri(_) => true
    _ => false
  } noraise {
    _ => false
  }
  assert_true(relative_path)
}

///|
test "protocol rejects non-integral IDs, malformed positions, and reversed ranges" {
  let non_integral_id = try
    classify_message("{\"jsonrpc\":\"2.0\",\"id\":1.5,\"result\":{}}")
  catch {
    InvalidMessage(_) => true
    _ => false
  } noraise {
    _ => false
  }
  assert_true(non_integral_id)

  let negative_position = try
    decode_publish_diagnostics(
      "{\"method\":\"textDocument/publishDiagnostics\",\"params\":{\"uri\":\"file:///x\",\"diagnostics\":[{\"range\":{\"start\":{\"line\":-1,\"character\":0},\"end\":{\"line\":0,\"character\":0}},\"message\":\"bad\"}]}}",
    )
  catch {
    InvalidDiagnostic(_) => true
    _ => false
  } noraise {
    _ => false
  }
  assert_true(negative_position)

  let reversed_range = try
    decode_publish_diagnostics(
      "{\"method\":\"textDocument/publishDiagnostics\",\"params\":{\"uri\":\"file:///x\",\"diagnostics\":[{\"range\":{\"start\":{\"line\":2,\"character\":3},\"end\":{\"line\":2,\"character\":2}},\"message\":\"bad\"}]}}",
    )
  catch {
    InvalidDiagnostic(reason~) => reason == "range end precedes range start"
    _ => false
  } noraise {
    _ => false
  }
  assert_true(reversed_range)
}

///|
test "protocol preserves numeric diagnostic codes and optional versions" {
  let payload = "{\"method\":\"textDocument/publishDiagnostics\",\"params\":{\"uri\":\"file:///tmp/main.mbt\",\"version\":7,\"diagnostics\":[{\"range\":{\"start\":{\"line\":0,\"character\":0},\"end\":{\"line\":0,\"character\":0}},\"severity\":2,\"code\":4021,\"message\":\"numeric code\"}]}}"
  let snapshot = decode_publish_diagnostics(payload).unwrap()
  assert_eq(snapshot.version, Some(7))
  assert_false(snapshot.unversioned)
  assert_eq(snapshot.diagnostics[0].code, Some(Number(4021)))
  assert_eq(snapshot.diagnostics[0].severity, Some(Warning))
}
