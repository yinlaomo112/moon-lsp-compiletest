///|
/// Native process or LSP lifecycle failure.  It remains internal; the facade
/// converts it to the public `RunnerError`/`CaseResult` boundary.
pub(all) suberror SessionError {
  InvalidOptions(reason~ : String)
  SpawnFailed(reason~ : String)
  IoFailed(operation~ : String, reason~ : String)
  ProtocolFailed(reason~ : String)
  Timeout(operation~ : String, timeout_ms~ : Int)
  EarlyExit(status~ : Int)
  TraceFailed(path~ : String, reason~ : String)
} derive(Debug, Eq)

///|
/// Native `moon-lsp --stdio` process session.
declare pub type Session

///|
/// Start the server and complete initialize/initialized.
declare pub async fn start(
  server_command : String,
  cwd : String,
  timeout_ms : Int,
  trace_path : String?,
) -> Session raise SessionError

///|
declare pub async fn Session::open_document(
  self : Session,
  uri : String,
  text : String,
  version : Int,
) -> Unit raise SessionError

///|
declare pub async fn Session::replace_document(
  self : Session,
  uri : String,
  old_text : String,
  new_text : String,
  version : Int,
) -> Unit raise SessionError

///|
/// Wait for a target-URI notification followed by a quiet window.
declare pub async fn Session::await_diagnostics(
  self : Session,
  uri : String,
  timeout_ms : Int,
  quiet_window_ms : Int,
) -> @model.DiagnosticSnapshot raise SessionError

///|
declare pub async fn Session::close_document(
  self : Session,
  uri : String,
) -> Unit raise SessionError

///|
/// Prefer protocol shutdown; cancel the process only after timeout.
declare pub async fn Session::shutdown(
  self : Session,
) -> Unit raise SessionError

///|
declare pub fn Session::trace_path(self : Session) -> String?

///|
declare pub fn Session::stderr_path(self : Session) -> String
