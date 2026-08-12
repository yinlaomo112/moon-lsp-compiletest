///|
extern "C" fn native_exit(status : Int) -> Unit = "exit"

///|
struct CliConfig {
  options : @tool.RunOptions
  cases : Array[String]
}

///|
let usage : String = "Usage: moon-lsp-compiletest [--server PATH] [--timeout-ms N] [--quiet-window-ms N] [--trace] CASE_DIR...\n"

///|
fn parse_positive(
  name : String,
  value : String,
  allow_zero~ : Bool,
) -> Result[Int, String] {
  let parsed : Int = @strconv.from_str(value) catch {
    _ => return Err("\{name} must be an integer")
  }
  if parsed < 0 || (!allow_zero && parsed == 0) {
    Err("\{name} has an invalid value: \{value}")
  } else {
    Ok(parsed)
  }
}

///|
fn parse_args(args : Array[String]) -> Result[CliConfig?, String] {
  let mut server_command = "moon-lsp"
  let mut timeout_ms = 5000
  let mut quiet_window_ms = 50
  let mut trace = false
  let cases = []
  let mut index = 1
  while index < args.length() {
    match args[index] {
      "--help" | "-h" => return Ok(None)
      "--trace" => trace = true
      "--server" => {
        if index + 1 == args.length() {
          return Err("--server requires PATH")
        }
        index += 1
        server_command = args[index]
      }
      "--timeout-ms" => {
        if index + 1 == args.length() {
          return Err("--timeout-ms requires N")
        }
        index += 1
        match parse_positive("--timeout-ms", args[index], allow_zero=false) {
          Ok(value) => timeout_ms = value
          Err(message) => return Err(message)
        }
      }
      "--quiet-window-ms" => {
        if index + 1 == args.length() {
          return Err("--quiet-window-ms requires N")
        }
        index += 1
        match
          parse_positive("--quiet-window-ms", args[index], allow_zero=true) {
          Ok(value) => quiet_window_ms = value
          Err(message) => return Err(message)
        }
      }
      argument if argument.has_prefix("--") =>
        return Err("unknown option: \{argument}")
      case_dir => cases.push(case_dir)
    }
    index += 1
  }
  if cases.is_empty() {
    Err("at least one CASE_DIR is required")
  } else {
    Ok(
      Some({
        options: { server_command, timeout_ms, quiet_window_ms, trace },
        cases,
      }),
    )
  }
}

///|
fn result_exit_code(results : ArrayView[@tool.CaseResult]) -> Int {
  let mut assertion_failed = false
  for result in results {
    match result.status {
      InfrastructureFailed => return 2
      AssertionFailed => assertion_failed = true
      Passed => ()
    }
  }
  if assertion_failed {
    1
  } else {
    0
  }
}

///|
fn render_infrastructure_errors(
  results : ArrayView[@tool.CaseResult],
) -> String {
  let output = StringBuilder()
  for result in results {
    if result.status == InfrastructureFailed {
      output.write_string("infrastructure failure: ")
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
  }
  output.to_string()
}

///|
async fn main {
  match parse_args(@env.args()) {
    Err(message) => {
      @stdio.stderr.write("error: \{message}\n\{usage}")
      native_exit(2)
    }
    Ok(None) => {
      @stdio.stdout.write(usage)
      native_exit(0)
    }
    Ok(Some(config)) => {
      let results = @tool.run_suite(config.cases, config.options) catch {
        err => {
          @stdio.stderr.write("error: \{@debug.to_string(err)}\n")
          native_exit(2)
          []
        }
      }
      @stdio.stdout.write(@tool.render_report(results))
      let exit_code = result_exit_code(results)
      if exit_code == 2 {
        @stdio.stderr.write(render_infrastructure_errors(results))
      }
      native_exit(exit_code)
    }
  }
}
