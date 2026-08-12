///|
test "CLI parser accepts defaults and rejects invalid invocations" {
  let parsed = parse_args(["moon-lsp-compiletest", "tests/cases"])
    .unwrap()
    .unwrap()
  assert_eq(parsed.options.server_command, "moon-lsp")
  assert_eq(parsed.options.timeout_ms, 5000)
  assert_eq(parsed.options.quiet_window_ms, 50)
  assert_false(parsed.options.trace)
  assert_eq(parsed.cases, ["tests/cases"])

  assert_true(parse_args(["moon-lsp-compiletest", "--help"]).unwrap() is None)
  assert_true(parse_args(["moon-lsp-compiletest"]) is Err(_))
  assert_true(
    parse_args(["moon-lsp-compiletest", "--timeout-ms", "0", "tests/cases"])
    is Err(_),
  )
  assert_true(
    parse_args(["moon-lsp-compiletest", "--unknown", "tests/cases"]) is Err(_),
  )
}

///|
test "CLI exit status prioritizes infrastructure failures" {
  let assertion_only : Array[@tool.CaseResult] = [
    {
      name: "assertion",
      status: AssertionFailed,
      before: None,
      after: None,
      differences: [],
      trace_path: None,
      stderr_path: None,
    },
  ]
  let infrastructure : Array[@tool.CaseResult] = [
    assertion_only[0],
    {
      name: "infrastructure",
      status: InfrastructureFailed,
      before: None,
      after: None,
      differences: [],
      trace_path: None,
      stderr_path: None,
    },
  ]
  assert_eq(result_exit_code([]), 0)
  assert_eq(result_exit_code(assertion_only), 1)
  assert_eq(result_exit_code(infrastructure), 2)
}

///|
test "CLI parser preserves case order and validates every numeric option" {
  let configured = parse_args([
      "moon-lsp-compiletest", "--server", "/tmp/mock-server", "--timeout-ms", "1200",
      "--quiet-window-ms", "0", "--trace", "first-case", "second-case",
    ])
    .unwrap()
    .unwrap()
  assert_eq(configured.options.server_command, "/tmp/mock-server")
  assert_eq(configured.options.timeout_ms, 1200)
  assert_eq(configured.options.quiet_window_ms, 0)
  assert_true(configured.options.trace)
  assert_eq(configured.cases, ["first-case", "second-case"])

  assert_true(parse_args(["moon-lsp-compiletest", "--server"]) is Err(_))
  assert_true(
    parse_args(["moon-lsp-compiletest", "--timeout-ms", "nope", "case"])
    is Err(_),
  )
  assert_true(
    parse_args(["moon-lsp-compiletest", "--quiet-window-ms", "-1", "case"])
    is Err(_),
  )
  assert_true(
    parse_args([
      "moon-lsp-compiletest", "--timeout-ms", "999999999999999999999", "case",
    ])
    is Err(_),
  )
}

///|
test "CLI writes infrastructure evidence to stderr without mixing assertion diffs" {
  let results : Array[@tool.CaseResult] = [
    {
      name: "assertion",
      status: AssertionFailed,
      before: None,
      after: None,
      differences: ["missing diagnostic"],
      trace_path: None,
      stderr_path: None,
    },
    {
      name: "server",
      status: InfrastructureFailed,
      before: None,
      after: None,
      differences: ["broken pipe"],
      trace_path: Some("/tmp/trace.log"),
      stderr_path: Some("/tmp/server.stderr"),
    },
  ]
  assert_eq(
    render_infrastructure_errors(results),
    "infrastructure failure: server\n  broken pipe\n  trace: /tmp/trace.log\n  stderr: /tmp/server.stderr\n",
  )
}
