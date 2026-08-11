///|
let maximum_case_source_bytes : Int64 = 1_048_576L

///|
pub async fn run_case(
  case_dir : String,
  options : @model.RunOptions,
) -> @model.CaseResult raise @model.RunnerError {
  validate_options(options)
  let canonical_case_dir = @fs.realpath(case_dir) catch {
    err =>
      raise InvalidCase(
        path=case_dir,
        reason="cannot resolve case directory: " + err.to_string(),
      )
  }
  let name = case_name(canonical_case_dir)
  let before_source = read_case_source(canonical_case_dir, "before.mbt")
  let after_source = read_case_source(canonical_case_dir, "after.mbt")
  let before_expectations = @marker.parse_expectations(before_source, Before) catch {
    err =>
      raise InvalidCase(
        path=canonical_case_dir + "/before.mbt",
        reason=@debug.to_string(err),
      )
  }
  let after_expectations = @marker.parse_expectations(after_source, After) catch {
    err =>
      raise InvalidCase(
        path=canonical_case_dir + "/after.mbt",
        reason=@debug.to_string(err),
      )
  }
  let workspace = @fs.tmpdir(prefix="moon-lsp-compiletest-") catch {
    err =>
      return infrastructure_result(
        name,
        "cannot create workspace: " + err.to_string(),
        None,
        None,
        None,
        None,
      )
  }
  let trace_path = workspace + "/session-\{@async.now()}.trace.log"
  let stderr_path = trace_path + ".stderr"
  let target_path = workspace + "/src/case.mbt"
  let setup_ok = try {
    prepare_workspace(workspace, before_source)
    Ok(())
  } catch {
    err => Err(@debug.to_string(err))
  } noraise {
    result => result
  }
  match setup_ok {
    Err(reason) =>
      return infrastructure_result(
        name,
        reason,
        None,
        None,
        Some(trace_path),
        Some(stderr_path),
      )
    Ok(_) => ()
  }
  let uri = @protocol.path_to_file_uri(target_path) catch {
    err =>
      return infrastructure_result(
        name,
        "cannot construct target URI: " + @debug.to_string(err),
        None,
        None,
        Some(trace_path),
        Some(stderr_path),
      )
  }
  let session = @session.start(
    options.server_command,
    workspace,
    options.timeout_ms,
    Some(trace_path),
  ) catch {
    err =>
      return infrastructure_result(
        name,
        "cannot start LSP session: " + @debug.to_string(err),
        None,
        None,
        Some(trace_path),
        Some(stderr_path),
      )
  }
  session.open_document(uri, before_source, 1) catch {
    err => {
      cleanup_failed_session(session, uri) catch {
        _ => ()
      }
      return infrastructure_result(
        name,
        "didOpen failed: " + @debug.to_string(err),
        None,
        None,
        session.trace_path(),
        Some(session.stderr_path()),
      )
    }
  }
  // moon-lsp does not analyse a byte-identical didChange on every version.
  // Append ignorable trailing whitespace to make the v2 update observable
  // without changing the parsed program or any expected diagnostic position.
  let before_trigger_source = before_source + " "
  write_workspace_source(target_path, before_trigger_source)
  session.replace_document(uri, before_source, before_trigger_source, 2) catch {
    err => {
      cleanup_failed_session(session, uri) catch {
        _ => ()
      }
      return infrastructure_result(
        name,
        "before didChange failed: " + @debug.to_string(err),
        None,
        None,
        session.trace_path(),
        Some(session.stderr_path()),
      )
    }
  }
  let before = session.await_diagnostics(
    uri,
    options.timeout_ms,
    options.quiet_window_ms,
  ) catch {
    err => {
      cleanup_failed_session(session, uri) catch {
        _ => ()
      }
      return infrastructure_result(
        name,
        "before diagnostics failed: " + @debug.to_string(err),
        None,
        None,
        session.trace_path(),
        Some(session.stderr_path()),
      )
    }
  }
  let before_report = @matcher.compare(before_expectations, before.diagnostics)
  write_workspace_source(target_path, after_source)
  session.replace_document(uri, before_trigger_source, after_source, 3) catch {
    err => {
      cleanup_failed_session(session, uri) catch {
        _ => ()
      }
      return infrastructure_result(
        name,
        "after didChange failed: " + @debug.to_string(err),
        Some(before),
        None,
        session.trace_path(),
        Some(session.stderr_path()),
      )
    }
  }
  let after = session.await_diagnostics(
    uri,
    options.timeout_ms,
    options.quiet_window_ms,
  ) catch {
    err => {
      cleanup_failed_session(session, uri) catch {
        _ => ()
      }
      return infrastructure_result(
        name,
        "after diagnostics failed: " + @debug.to_string(err),
        Some(before),
        None,
        session.trace_path(),
        Some(session.stderr_path()),
      )
    }
  }
  let after_report = @matcher.compare(after_expectations, after.diagnostics)
  session.close_document(uri) catch {
    err => {
      cleanup_failed_session(session, uri) catch {
        _ => ()
      }
      return infrastructure_result(
        name,
        "didClose failed: " + @debug.to_string(err),
        Some(before),
        Some(after),
        session.trace_path(),
        Some(session.stderr_path()),
      )
    }
  }
  session.shutdown() catch {
    err =>
      return infrastructure_result(
        name,
        "shutdown failed: " + @debug.to_string(err),
        Some(before),
        Some(after),
        session.trace_path(),
        Some(session.stderr_path()),
      )
  }
  let differences = prefixed_differences("before", before_report.differences)
  for difference in prefixed_differences("after", after_report.differences) {
    differences.push(difference)
  }
  let result : @model.CaseResult = {
    name,
    status: if before_report.passed && after_report.passed {
      Passed
    } else {
      AssertionFailed
    },
    before: Some(before),
    after: Some(after),
    differences,
    trace_path: if options.trace {
      session.trace_path()
    } else {
      None
    },
    stderr_path: None,
  }
  if !options.trace {
    @fs.rmdir(workspace, recursive=true) catch {
      _ => ()
    }
  }
  result
}

///|
pub async fn run_suite(
  case_dirs : ArrayView[String],
  options : @model.RunOptions,
) -> Array[@model.CaseResult] raise @model.RunnerError {
  validate_options(options)
  let results = []
  for input in case_dirs {
    let expanded = discover_cases(input)
    for case_dir in expanded {
      results.push(run_case(case_dir, options))
    }
  }
  results
}

///|
pub fn render_report(results : ArrayView[@model.CaseResult]) -> String {
  let output = StringBuilder()
  let mut passed = 0
  let mut assertion_failed = 0
  let mut infrastructure_failed = 0
  for result in results {
    match result.status {
      Passed => {
        passed += 1
        output.write_string("PASS ")
      }
      AssertionFailed => {
        assertion_failed += 1
        output.write_string("FAIL ")
      }
      InfrastructureFailed => {
        infrastructure_failed += 1
        output.write_string("ERROR ")
      }
    }
    output.write_string(result.name)
    output.write_char('\n')
    for difference in result.differences {
      output.write_string("  ")
      output.write_string(difference)
      output.write_char('\n')
    }
    match result.trace_path {
      Some(path) => output.write_string("  trace: \{path}\n")
      None => ()
    }
    match result.stderr_path {
      Some(path) => output.write_string("  stderr: \{path}\n")
      None => ()
    }
  }
  output.write_string(
    "summary: passed=\{passed} assertion-failed=\{assertion_failed} infrastructure-failed=\{infrastructure_failed}\n",
  )
  output.to_string()
}

///|
fn validate_options(
  options : @model.RunOptions,
) -> Unit raise @model.RunnerError {
  if options.server_command.trim().to_owned().is_empty() {
    raise InvalidOptions(reason="server_command must not be empty")
  }
  if options.timeout_ms <= 0 {
    raise InvalidOptions(reason="timeout_ms must be positive")
  }
  if options.quiet_window_ms < 0 {
    raise InvalidOptions(reason="quiet_window_ms must not be negative")
  }
}

///|
async fn read_case_source(
  case_dir : String,
  name : String,
) -> String raise @model.RunnerError {
  let path = case_dir + "/" + name
  let exists = @fs.exists(path) catch {
    err =>
      raise InvalidCase(
        path~,
        reason="cannot inspect required case file: " + err.to_string(),
      )
  }
  if !exists {
    raise InvalidCase(path~, reason="required file is missing")
  }
  let file = @fs.open(path, mode=ReadOnly) catch {
    err =>
      raise InvalidCase(
        path~,
        reason="cannot open case file: " + err.to_string(),
      )
  }
  defer file.close()
  let size = file.size() catch {
    err =>
      raise InvalidCase(
        path~,
        reason="cannot stat case file: " + err.to_string(),
      )
  }
  if size < 0L || size > maximum_case_source_bytes {
    raise InvalidCase(path~, reason="case file must be at most 1 MiB")
  }
  let bytes = file.read_exactly(size.to_int()) catch {
    err =>
      raise InvalidCase(
        path~,
        reason="cannot read case file: " + err.to_string(),
      )
  }
  @utf8.decode(bytes) catch {
    _ => raise InvalidCase(path~, reason="case file is not valid UTF-8")
  }
}

///|
async fn prepare_workspace(
  workspace : String,
  source : String,
) -> Unit raise @model.RunnerError {
  @fs.mkdir(workspace + "/src") catch {
    err =>
      raise SessionFailed(
        case_name="workspace",
        reason="cannot create workspace source directory: " + err.to_string(),
      )
  }
  @fs.write_file(
    workspace + "/moon.mod",
    "name = \"compiletest_case\"\nversion = \"0.1.0\"\nsource = \"src\"\n",
    create_mode=CreateOrTruncate,
    permission=0o644,
  ) catch {
    err =>
      raise SessionFailed(
        case_name="workspace",
        reason="cannot write workspace moon.mod: " + err.to_string(),
      )
  }
  @fs.write_file(
    workspace + "/src/moon.pkg",
    "supported_targets = \"native\"\n",
    create_mode=CreateOrTruncate,
    permission=0o644,
  ) catch {
    err =>
      raise SessionFailed(
        case_name="workspace",
        reason="cannot write workspace package file: " + err.to_string(),
      )
  }
  @fs.write_file(
    workspace + "/src/case.mbt",
    source,
    create_mode=CreateOrTruncate,
    permission=0o644,
  ) catch {
    err =>
      raise SessionFailed(
        case_name="workspace",
        reason="cannot write workspace source: " + err.to_string(),
      )
  }
  // moon-lsp consumes this generated package index when converting compiler
  // output to publishDiagnostics. A failing source check is expected for a
  // before revision, but moon still writes the index before returning its
  // non-zero diagnostic status.
  let bootstrap_stdout = @process.redirect_to_file(
    workspace + "/bootstrap-check.stdout.log",
    append=false,
    create_mode=CreateOrTruncate,
    permission=0o644,
  ) catch {
    err =>
      raise SessionFailed(
        case_name="workspace",
        reason="cannot capture workspace-index stdout: " + err.to_string(),
      )
  }
  let bootstrap_stderr = @process.redirect_to_file(
    workspace + "/bootstrap-check.stderr.log",
    append=false,
    create_mode=CreateOrTruncate,
    permission=0o644,
  ) catch {
    err =>
      raise SessionFailed(
        case_name="workspace",
        reason="cannot capture workspace-index stderr: " + err.to_string(),
      )
  }
  let _ = @process.run(
    "moon",
    ["check", "--target", "native"],
    stdout=bootstrap_stdout,
    stderr=bootstrap_stderr,
    cwd=workspace,
  ) catch {
    err =>
      raise SessionFailed(
        case_name="workspace",
        reason="cannot create MoonBit workspace index: " + err.to_string(),
      )
  }
}

///|
async fn write_workspace_source(
  path : String,
  source : String,
) -> Unit raise @model.RunnerError {
  @fs.write_file(path, source, create_mode=TruncateExisting, permission=0o644) catch {
    err =>
      raise SessionFailed(
        case_name="workspace",
        reason="cannot update workspace source: " + err.to_string(),
      )
  }
}

///|
async fn cleanup_failed_session(
  session : @session.Session,
  uri : String,
) -> Unit raise @model.RunnerError {
  session.close_document(uri) catch {
    err =>
      raise SessionFailed(
        case_name="session",
        reason="failed to close failed session: " + @debug.to_string(err),
      )
  }
  session.shutdown() catch {
    err =>
      raise SessionFailed(
        case_name="session",
        reason="failed to shut down failed session: " + @debug.to_string(err),
      )
  }
}

///|
async fn discover_cases(
  input : String,
) -> Array[String] raise @model.RunnerError {
  let canonical = @fs.realpath(input) catch {
    err =>
      raise InvalidCase(
        path=input,
        reason="cannot resolve input: " + err.to_string(),
      )
  }
  let own_before = @fs.exists(canonical + "/before.mbt") catch {
    err => raise InvalidCase(path=canonical, reason=err.to_string())
  }
  let own_after = @fs.exists(canonical + "/after.mbt") catch {
    err => raise InvalidCase(path=canonical, reason=err.to_string())
  }
  if own_before || own_after {
    if own_before && own_after {
      return [canonical]
    }
    raise InvalidCase(
      path=canonical,
      reason="case directory must contain both before.mbt and after.mbt",
    )
  }
  let entries = @fs.readdir(canonical, sort=true) catch {
    err =>
      raise InvalidCase(
        path=canonical,
        reason="cannot read directory: " + err.to_string(),
      )
  }
  // The filesystem helper's `sort` parameter is platform-specific for
  // directory-entry representations. Sort the final names explicitly using
  // code-point lexical order so one directory argument has reproducible,
  // familiar case order independent of the runtime's length-first String
  // Compare implementation.
  entries.sort_by(compare_case_entry)
  let cases = []
  for entry in entries {
    let child = canonical + "/" + entry
    let before = @fs.exists(child + "/before.mbt") catch { _ => false }
    let after = @fs.exists(child + "/after.mbt") catch { _ => false }
    if before || after {
      if !before || !after {
        raise InvalidCase(
          path=child,
          reason="case directory must contain both before.mbt and after.mbt",
        )
      }
      cases.push(child)
    }
  }
  if cases.is_empty() {
    raise InvalidCase(path=canonical, reason="no case directory was found")
  }
  cases
}

///|
fn case_name(path : String) -> String {
  let parts = path.split("/").to_array()
  if parts.length() == 0 {
    path
  } else {
    parts[parts.length() - 1].to_owned()
  }
}

///|
fn compare_case_entry(left : String, right : String) -> Int {
  let left_chars = left.to_array()
  let right_chars = right.to_array()
  let common_length = if left_chars.length() < right_chars.length() {
    left_chars.length()
  } else {
    right_chars.length()
  }
  for index in 0..<common_length {
    let order = left_chars[index].to_int().compare(right_chars[index].to_int())
    if order != 0 {
      return order
    }
  }
  left_chars.length().compare(right_chars.length())
}

///|
fn prefixed_differences(
  prefix : String,
  values : ArrayView[String],
) -> Array[String] {
  let result = []
  for value in values {
    result.push("[\{prefix}] \{value}")
  }
  result
}

///|
fn infrastructure_result(
  name : String,
  reason : String,
  before : @model.DiagnosticSnapshot?,
  after : @model.DiagnosticSnapshot?,
  trace_path : String?,
  stderr_path : String?,
) -> @model.CaseResult {
  {
    name,
    status: InfrastructureFailed,
    before,
    after,
    differences: [reason],
    trace_path,
    stderr_path,
  }
}
