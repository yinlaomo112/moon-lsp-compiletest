///|
/// Stable public model.
pub using @model {
  type CaseResult,
  type CaseSpec,
  type CaseStatus,
  type Diagnostic,
  type DiagnosticCode,
  type DiagnosticSnapshot,
  type Expectation,
  type Position,
  type Range,
  type RunOptions,
  type RunnerError,
  type Severity,
  type Stage,
}

///|
/// Load one case directory, create an isolated workspace and run both stages.
declare pub async fn run_case(
  case_dir : String,
  options : @model.RunOptions,
) -> @model.CaseResult raise @model.RunnerError

///|
/// Run case directories sequentially and preserve input order in the report.
declare pub async fn run_suite(
  case_dirs : ArrayView[String],
  options : @model.RunOptions,
) -> Array[@model.CaseResult] raise @model.RunnerError

///|
/// Render deterministic human-readable output for CLI and CI logs.
declare pub fn render_report(results : ArrayView[@model.CaseResult]) -> String
