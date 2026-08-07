///|
async fn mock_binary() -> String {
  @fs.realpath("_build/native/debug/build/test/mock_lsp/mock_lsp.exe") catch {
    err =>
      abort("mock_lsp must be built before session tests: " + err.to_string())
  }
}

///|
async fn mock_workspace(scenario : String) -> String {
  let directory = @fs.tmpdir(prefix="moon-lsp-compiletest-session-test-")
  @fs.write_file(
    directory + "/.moon-lsp-compiletest-mock-scenario",
    scenario,
    create_mode=CreateOrTruncate,
    permission=0o644,
  )
  directory
}

///|
async test "session handles colliding server request ids and explicit clear" {
  let workspace = mock_workspace("id-collision")
  let trace = workspace + "/trace.log"
  let uri = @protocol.path_to_file_uri(workspace + "/case.mbt") catch {
    err => abort(@debug.to_string(err))
  }
  let session = start(mock_binary(), workspace, 1000, Some(trace)) catch {
    err => abort(@debug.to_string(err))
  }
  session.open_document(uri, "bad\n", 1) catch {
    err => abort(@debug.to_string(err))
  }
  session.replace_document(uri, "bad\n", "bad\n", 2) catch {
    err => abort(@debug.to_string(err))
  }
  let before = session.await_diagnostics(uri, 1000, 0) catch {
    err => abort(@debug.to_string(err))
  }
  assert_eq(before.diagnostics.length(), 1)
  session.replace_document(uri, "bad\n", "fixed\n", 3) catch {
    err => abort(@debug.to_string(err))
  }
  let after = session.await_diagnostics(uri, 1000, 0) catch {
    err => abort(@debug.to_string(err))
  }
  assert_eq(after.diagnostics.length(), 0)
  session.close_document(uri) catch {
    err => abort(@debug.to_string(err))
  }
  session.shutdown() catch {
    err => abort(@debug.to_string(err))
  }
  @fs.rmdir(workspace, recursive=true) catch {
    _ => ()
  }
}

///|
async test "session ignores diagnostics for another URI" {
  let workspace = mock_workspace("multi-uri")
  let trace = workspace + "/trace.log"
  let uri = @protocol.path_to_file_uri(workspace + "/case.mbt") catch {
    err => abort(@debug.to_string(err))
  }
  let session = start(mock_binary(), workspace, 1000, Some(trace)) catch {
    err => abort(@debug.to_string(err))
  }
  session.open_document(uri, "bad\n", 1) catch {
    err => abort(@debug.to_string(err))
  }
  session.replace_document(uri, "bad\n", "bad\n", 2) catch {
    err => abort(@debug.to_string(err))
  }
  let snapshot = session.await_diagnostics(uri, 1000, 0) catch {
    err => abort(@debug.to_string(err))
  }
  assert_eq(snapshot.uri, uri)
  session.close_document(uri) catch {
    err => abort(@debug.to_string(err))
  }
  session.shutdown() catch {
    err => abort(@debug.to_string(err))
  }
  @fs.rmdir(workspace, recursive=true) catch {
    _ => ()
  }
}

///|
async test "session captures noisy stderr and surfaces non-success scenarios" {
  let stderr_workspace = mock_workspace("stderr-flood")
  let stderr_trace = stderr_workspace + "/trace.log"
  let stderr_uri = @protocol.path_to_file_uri(stderr_workspace + "/case.mbt") catch {
    err => abort(@debug.to_string(err))
  }
  let stderr_session = start(
    mock_binary(),
    stderr_workspace,
    1000,
    Some(stderr_trace),
  ) catch {
    err => abort(@debug.to_string(err))
  }
  stderr_session.open_document(stderr_uri, "bad\n", 1) catch {
    err => abort(@debug.to_string(err))
  }
  stderr_session.replace_document(stderr_uri, "bad\n", "bad\n", 2) catch {
    err => abort(@debug.to_string(err))
  }
  let _ = stderr_session.await_diagnostics(stderr_uri, 1000, 0) catch {
    err => abort(@debug.to_string(err))
  }
  assert_true(@fs.exists(stderr_session.stderr_path()))
  stderr_session.close_document(stderr_uri) catch {
    err => abort(@debug.to_string(err))
  }
  stderr_session.shutdown() catch {
    err => abort(@debug.to_string(err))
  }
  @fs.rmdir(stderr_workspace, recursive=true) catch {
    _ => ()
  }

  let early_workspace = mock_workspace("early-exit")
  let early_failed = try {
    let _ = start(mock_binary(), early_workspace, 200, None)
    false
  } catch {
    _ => true
  } noraise {
    _ => false
  }
  assert_true(early_failed)
  @fs.rmdir(early_workspace, recursive=true) catch {
    _ => ()
  }

  let timeout_workspace = mock_workspace("timeout")
  let timeout_uri = @protocol.path_to_file_uri(timeout_workspace + "/case.mbt") catch {
    err => abort(@debug.to_string(err))
  }
  let timeout_session = start(mock_binary(), timeout_workspace, 500, None) catch {
    err => abort(@debug.to_string(err))
  }
  timeout_session.open_document(timeout_uri, "bad\n", 1) catch {
    err => abort(@debug.to_string(err))
  }
  timeout_session.replace_document(timeout_uri, "bad\n", "bad\n", 2) catch {
    err => abort(@debug.to_string(err))
  }
  let timed_out = try {
    let _ = timeout_session.await_diagnostics(timeout_uri, 100, 0)
    false
  } catch {
    _ => true
  } noraise {
    _ => false
  }
  assert_true(timed_out)
  timeout_session.terminate() catch {
    _ => ()
  }
  @fs.rmdir(timeout_workspace, recursive=true) catch {
    _ => ()
  }
}

///|
async test "session classifies an unfinished server frame as a protocol failure" {
  let workspace = mock_workspace("partial-frame")
  let uri = @protocol.path_to_file_uri(workspace + "/case.mbt") catch {
    err => abort(@debug.to_string(err))
  }
  let session = start(mock_binary(), workspace, 1000, None) catch {
    err => abort(@debug.to_string(err))
  }
  session.open_document(uri, "bad\n", 1) catch {
    err => abort(@debug.to_string(err))
  }
  session.replace_document(uri, "bad\n", "bad\n", 2) catch {
    err => abort(@debug.to_string(err))
  }
  let early_exit = try {
    let _ = session.await_diagnostics(uri, 1000, 0)
    false
  } catch {
    ProtocolFailed(reason~) => reason.contains("UnexpectedEof")
    _ => false
  } noraise {
    _ => false
  }
  assert_true(early_exit)
  session.terminate() catch {
    _ => ()
  }
  @fs.rmdir(workspace, recursive=true) catch {
    _ => ()
  }
}
