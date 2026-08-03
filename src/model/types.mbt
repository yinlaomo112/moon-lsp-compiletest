///|
/// Diagnostic collection stage in a two-revision case.
pub(all) enum Stage {
  Before
  After
} derive(Debug, Eq)

///|
/// LSP diagnostic severity supported by the first release.
pub(all) enum Severity {
  Error
  Warning
  Information
  Hint
} derive(Debug, Eq)

///|
/// LSP permits either a string or numeric diagnostic code.
pub(all) enum DiagnosticCode {
  Text(String)
  Number(Int)
} derive(Debug, Eq)

///|
/// Zero-based LSP position. `character` is a UTF-16 code-unit offset.
pub(all) struct Position {
  line : Int
  character : Int
} derive(Debug, Eq)

///|
/// Half-open LSP range.
pub(all) struct Range {
  start : Position
  end : Position
} derive(Debug, Eq)

///|
/// Normalized push diagnostic used by the matcher.
pub(all) struct Diagnostic {
  range : Range
  severity : Severity?
  code : DiagnosticCode?
  source : String?
  message : String
} derive(Debug, Eq)

///|
/// Source-inline expectation extracted from a `//~^` marker.
pub(all) struct Expectation {
  stage : Stage
  range : Range
  severity : Severity
  code : DiagnosticCode?
  message_substring : String
  marker_line : Int
} derive(Debug, Eq)

///|
/// A diagnostics notification normalized for one target URI.
pub(all) struct DiagnosticSnapshot {
  uri : String
  version : Int?
  diagnostics : Array[Diagnostic]
  unversioned : Bool
} derive(Debug, Eq)

///|
/// Input fixture for one isolated two-revision test case.
pub(all) struct CaseSpec {
  name : String
  case_dir : String
  before_source : String
  after_source : String
} derive(Debug, Eq)

///|
/// Stable runner options shared by the facade and CLI.
pub(all) struct RunOptions {
  server_command : String
  timeout_ms : Int
  quiet_window_ms : Int
  trace : Bool
} derive(Debug, Eq)

///|
/// Observable outcome of a case.
pub(all) enum CaseStatus {
  Passed
  AssertionFailed
  InfrastructureFailed
} derive(Debug, Eq)

///|
/// Result returned by the public facade.
pub(all) struct CaseResult {
  name : String
  status : CaseStatus
  before : DiagnosticSnapshot?
  after : DiagnosticSnapshot?
  differences : Array[String]
  trace_path : String?
  stderr_path : String?
} derive(Debug, Eq)

///|
/// Public errors that occur before or around a test session.
pub(all) suberror RunnerError {
  InvalidCase(path~ : String, reason~ : String)
  InvalidOptions(reason~ : String)
  SessionFailed(case_name~ : String, reason~ : String)
} derive(Debug, Eq)
