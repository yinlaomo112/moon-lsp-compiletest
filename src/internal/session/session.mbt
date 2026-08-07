///|
/// A single native stdio connection. Task groups own and cancel children at
/// scope exit, while this handle must survive the public session calls made by
/// the facade. stderr is redirected to a per-case file, so a verbose server
/// cannot block its stdout diagnostics on a full pipe.
pub struct Session {
  stdin : @process.WriteToProcess
  stdout : @process.ReadFromProcess
  decoder : @framing.FrameDecoder
  pending : Array[String]
  pid : Int
  timeout_ms : Int
  trace_path : String?
  stderr_path : String
  mut closed : Bool
}

///|
extern "C" fn native_getpid() -> Int = "getpid"

///|
pub fn Session::trace_path(self : Session) -> String? {
  self.trace_path
}

///|
pub fn Session::stderr_path(self : Session) -> String {
  self.stderr_path
}

///|
pub async fn start(
  server_command : String,
  cwd : String,
  timeout_ms : Int,
  trace_path : String?,
) -> Session raise SessionError {
  if server_command.trim().to_owned().is_empty() {
    raise InvalidOptions(reason="server command must not be empty")
  }
  if cwd.trim().to_owned().is_empty() {
    raise InvalidOptions(reason="server cwd must not be empty")
  }
  if timeout_ms <= 0 {
    raise InvalidOptions(reason="timeout_ms must be positive")
  }
  let (input, writer) = @process.write_to_process() catch {
    err => raise SpawnFailed(reason=err.to_string())
  }
  let (reader, output) = @process.read_from_process() catch {
    err => raise SpawnFailed(reason=err.to_string())
  }
  let stderr_path = match trace_path {
    Some(path) => path + ".stderr"
    None => cwd + "/.moon-lsp-compiletest.stderr.log"
  }
  let stderr = @process.redirect_to_file(
    stderr_path,
    append=false,
    create_mode=CreateOrTruncate,
    permission=0o644,
  ) catch {
    err =>
      raise SpawnFailed(
        reason="cannot open stderr evidence: " + err.to_string(),
      )
  }
  let client_process_id = native_getpid()
  let pid = @process.spawn_orphan(
    server_command,
    ["--stdio", "--clientProcessId=" + client_process_id.to_string()],
    stdin=input,
    stdout=output,
    stderr~,
    cwd~,
  ) catch {
    err => raise SpawnFailed(reason=err.to_string())
  }
  let session : Session = {
    stdin: writer,
    stdout: reader,
    decoder: @framing.FrameDecoder::new(max_content_length=8_388_608),
    pending: [],
    pid,
    timeout_ms,
    trace_path,
    stderr_path,
    closed: false,
  }
  let root_uri = @protocol.path_to_file_uri(cwd) catch {
    err => {
      session.terminate()
      raise ProtocolFailed(reason=@debug.to_string(err))
    }
  }
  session.send(
    @protocol.encode_initialize(Number(1), root_uri, cwd, client_process_id),
  )
  let initialize_response = session.await_response(Number(1))
  @protocol.ensure_incremental_sync(initialize_response) catch {
    err => {
      session.terminate()
      raise ProtocolFailed(reason=@debug.to_string(err))
    }
  }
  session.send(@protocol.encode_initialized())
  // moon-lsp may finish workspace setup only after it consumes initialized.
  // Let that transition settle before the first tracked document lifecycle
  // event; any unsolicited messages remain available to the normal router.
  @async.sleep(50) catch {
    err =>
      raise IoFailed(operation="settle initialized", reason=err.to_string())
  }
  session
}

///|
pub async fn Session::open_document(
  self : Session,
  uri : String,
  text : String,
  version : Int,
) -> Unit raise SessionError {
  if version <= 0 {
    raise InvalidOptions(reason="document version must be positive")
  }
  self.send(@protocol.encode_did_open(uri, version, text))
}

///|
pub async fn Session::replace_document(
  self : Session,
  uri : String,
  old_text : String,
  new_text : String,
  version : Int,
) -> Unit raise SessionError {
  if version <= 0 {
    raise InvalidOptions(reason="document version must be positive")
  }
  self.send(@protocol.encode_did_change(uri, version, old_text, new_text))
  self.send(@protocol.encode_did_save(uri, new_text))
  self.send(@protocol.encode_watched_file_changed(uri))
}

///|
pub async fn Session::await_diagnostics(
  self : Session,
  uri : String,
  timeout_ms : Int,
  quiet_window_ms : Int,
) -> @model.DiagnosticSnapshot raise SessionError {
  if timeout_ms <= 0 {
    raise InvalidOptions(reason="diagnostic timeout must be positive")
  }
  if quiet_window_ms < 0 {
    raise InvalidOptions(reason="quiet window must not be negative")
  }
  let snapshot = @async.with_timeout_opt(timeout_ms, () => {
    self.await_target_then_quiet(uri, quiet_window_ms)
  }) catch {
    InvalidOptions(reason~) => raise InvalidOptions(reason~)
    IoFailed(operation~, reason~) => raise IoFailed(operation~, reason~)
    ProtocolFailed(reason~) => raise ProtocolFailed(reason~)
    EarlyExit(status~) => raise EarlyExit(status~)
    TraceFailed(path~, reason~) => raise TraceFailed(path~, reason~)
    err => raise IoFailed(operation="read diagnostics", reason=err.to_string())
  }
  match snapshot {
    Some(value) => value
    None => raise Timeout(operation="await publishDiagnostics", timeout_ms~)
  }
}

///|
pub async fn Session::close_document(
  self : Session,
  uri : String,
) -> Unit raise SessionError {
  self.send(@protocol.encode_did_close(uri))
}

///|
pub async fn Session::shutdown(self : Session) -> Unit raise SessionError {
  if self.closed {
    return
  }
  let graceful = try {
    self.send(@protocol.encode_shutdown(Number(2)))
    let _ = self.await_response(Number(2))
    self.send(@protocol.encode_exit())
    self.stdin.close()
    self.stdout.close()
    self.closed = true
    Ok(())
  } catch {
    err => Err(err)
  } noraise {
    result => result
  }
  match graceful {
    Ok(_) => ()
    Err(err) => {
      // Keep the original lifecycle/transport error observable, but do not
      // leave a failed server running solely because graceful shutdown could
      // not complete.
      self.terminate() catch {
        _ => ()
      }
      raise err
    }
  }
  // The orphan-spawn handle survives public session calls, but native
  // wait_pid is not cancellation-safe after both stdio ends. Protocol exit
  // plus closed pipes is the normal completion barrier; read/write/response
  // failures remain observable beforehand.
  ()
}

///|
async fn Session::send(
  self : Session,
  payload : String,
) -> Unit raise SessionError {
  self.append_trace("out", payload)
  let frame = @framing.encode_frame(payload)
  self.stdin.write(frame) catch {
    err => raise IoFailed(operation="write stdin", reason=err.to_string())
  }
}

///|
async fn Session::read_payload(self : Session) -> String raise SessionError {
  if !self.pending.is_empty() {
    let payload = self.pending.remove(0)
    self.append_trace("in", payload)
    return payload
  }
  while true {
    let chunk = self.stdout.read_some(max_len=8192) catch {
      err => raise IoFailed(operation="read stdout", reason=err.to_string())
    }
    match chunk {
      None => {
        self.decoder.finish() catch {
          err => raise ProtocolFailed(reason=@debug.to_string(err))
        }
        raise EarlyExit(status=-1)
      }
      Some(bytes) => {
        let payloads = self.decoder.feed(bytes) catch {
          err => raise ProtocolFailed(reason=@debug.to_string(err))
        }
        for payload in payloads {
          self.pending.push(payload)
        }
        if !self.pending.is_empty() {
          let payload = self.pending.remove(0)
          self.append_trace("in", payload)
          return payload
        }
      }
    }
  }
  abort("unreachable read loop")
}

///|
async fn Session::await_response(
  self : Session,
  expected_id : @protocol.RequestId,
) -> String raise SessionError {
  let response = @async.with_timeout_opt(self.timeout_ms, () => {
    while true {
      let payload = self.read_payload()
      let kind = @protocol.classify_message(payload) catch {
        err => raise ProtocolFailed(reason=@debug.to_string(err))
      }
      match kind {
        ServerRequest(id, _) => self.send(@protocol.encode_null_response(id))
        Response(id) if id == expected_id => return payload
        _ => ()
      }
    }
    abort("unreachable response loop")
  }) catch {
    InvalidOptions(reason~) => raise InvalidOptions(reason~)
    IoFailed(operation~, reason~) => raise IoFailed(operation~, reason~)
    ProtocolFailed(reason~) => raise ProtocolFailed(reason~)
    EarlyExit(status~) => raise EarlyExit(status~)
    TraceFailed(path~, reason~) => raise TraceFailed(path~, reason~)
    err => raise IoFailed(operation="await response", reason=err.to_string())
  }
  match response {
    Some(payload) => payload
    None =>
      raise Timeout(operation="await response", timeout_ms=self.timeout_ms)
  }
}

///|
async fn Session::await_target_then_quiet(
  self : Session,
  uri : String,
  quiet_window_ms : Int,
) -> @model.DiagnosticSnapshot raise SessionError {
  while true {
    let payload = self.read_payload()
    let kind = @protocol.classify_message(payload) catch {
      err => raise ProtocolFailed(reason=@debug.to_string(err))
    }
    match kind {
      ServerRequest(id, _) => self.send(@protocol.encode_null_response(id))
      Notification(method_name) if method_name ==
        "textDocument/publishDiagnostics" => {
        let snapshot = @protocol.decode_publish_diagnostics(payload) catch {
          err => raise ProtocolFailed(reason=@debug.to_string(err))
        }
        match snapshot {
          Some(snapshot) if snapshot.uri == uri =>
            return self.wait_for_quiet(uri, snapshot, quiet_window_ms)
          _ => ()
        }
      }
      _ => ()
    }
  }
  abort("unreachable diagnostic loop")
}

///|
async fn Session::wait_for_quiet(
  self : Session,
  uri : String,
  first : @model.DiagnosticSnapshot,
  quiet_window_ms : Int,
) -> @model.DiagnosticSnapshot raise SessionError {
  let _ = self
  let _ = uri
  // A timed read cannot currently preserve the narrow SessionError effect
  // while also distinguishing coroutine cancellation from an actual pipe
  // failure. Keep the connection intact for the bounded settling interval;
  // later notifications are consumed by the next lifecycle stage. This is a
  // documented unversioned-diagnostics limitation rather than a claim of
  // full event-loop convergence.
  if quiet_window_ms > 0 {
    @async.sleep(quiet_window_ms) catch {
      err =>
        raise IoFailed(operation="wait quiet window", reason=err.to_string())
    }
  }
  first
}

///|
async fn Session::append_trace(
  self : Session,
  direction : String,
  payload : String,
) -> Unit raise SessionError {
  match self.trace_path {
    None => ()
    Some(path) =>
      @fs.write_file(
        path,
        direction + " " + payload + "\n",
        append=true,
        create_mode=OpenOrCreate,
        permission=0o644,
      ) catch {
        err => raise TraceFailed(path~, reason=err.to_string())
      }
  }
}

///|
async fn Session::terminate(self : Session) -> Unit raise SessionError {
  self.stdin.close()
  self.stdout.close()
  let _ = @process.run("/bin/kill", ["-TERM", self.pid.to_string()]) catch {
    err => raise IoFailed(operation="terminate server", reason=err.to_string())
  }
  let _ = @process.run("/bin/kill", ["-KILL", self.pid.to_string()]) catch {
    err =>
      raise IoFailed(operation="hard terminate server", reason=err.to_string())
  }
}
