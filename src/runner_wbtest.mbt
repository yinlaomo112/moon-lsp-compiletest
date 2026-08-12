///|
async fn make_case(before : String, after : String) -> String {
  let directory = @fs.tmpdir(prefix="moon-lsp-compiletest-runner-test-")
  @fs.write_file(
    directory + "/before.mbt",
    before,
    create_mode=CreateOrTruncate,
    permission=0o644,
  )
  @fs.write_file(
    directory + "/after.mbt",
    after,
    create_mode=CreateOrTruncate,
    permission=0o644,
  )
  directory
}

///|
async fn make_named_case(
  root : String,
  name : String,
  before : String,
  after : String,
) -> String {
  let directory = root + "/" + name
  @fs.mkdir(directory) catch {
    err => abort("cannot create named case: " + err.to_string())
  }
  @fs.write_file(
    directory + "/before.mbt",
    before,
    create_mode=CreateOrTruncate,
    permission=0o644,
  ) catch {
    err => abort("cannot write named before case: " + err.to_string())
  }
  @fs.write_file(
    directory + "/after.mbt",
    after,
    create_mode=CreateOrTruncate,
    permission=0o644,
  ) catch {
    err => abort("cannot write named after case: " + err.to_string())
  }
  directory
}

///|
async fn mock_server_path() -> String {
  @fs.realpath("_build/native/debug/build/test/mock_lsp/mock_lsp.exe") catch {
    err =>
      abort(
        "mock_lsp must be built before root integration tests: " +
        err.to_string(),
      )
  }
}

///|
async test "runner executes before and explicit-empty after against mock LSP" {
  let case_dir = make_case(
    "missing_symbol\n//~^ ERROR [E4021] \"mock unresolved\"\n", "let fixed = 1\n",
  )
  let result = run_case(case_dir, {
    server_command: mock_server_path(),
    timeout_ms: 1000,
    quiet_window_ms: 10,
    trace: true,
  }) catch {
    err => abort(@debug.to_string(err))
  }
  if result.status != Passed {
    abort(render_report([result]))
  }
  assert_true(result.before is Some(before) && before.unversioned)
  assert_true(result.after is Some(after) && after.diagnostics.length() == 0)
  assert_true(result.trace_path is Some(_))
  @fs.rmdir(case_dir, recursive=true) catch {
    _ => ()
  }
}

///|
async test "runner rejects a case missing its after revision" {
  let directory = @fs.tmpdir(prefix="moon-lsp-compiletest-invalid-case-")
  @fs.write_file(
    directory + "/before.mbt",
    "let value = 1\n",
    create_mode=CreateOrTruncate,
    permission=0o644,
  )
  let rejected = try {
    let _ = run_case(directory, {
      server_command: "/bin/true",
      timeout_ms: 1000,
      quiet_window_ms: 0,
      trace: false,
    })
    false
  } catch {
    InvalidCase(..) => true
    _ => false
  } noraise {
    _ => false
  }
  assert_true(rejected)
  @fs.rmdir(directory, recursive=true) catch {
    _ => ()
  }
}

///|
async test "runner reports marker mismatches as assertion failures, not infrastructure failures" {
  let case_dir = make_case(
    "missing_symbol\n//~^ ERROR [E4021] \"intentionally different\"\n", "let fixed = 1\n",
  )
  let result = run_case(case_dir, {
    server_command: mock_server_path(),
    timeout_ms: 1000,
    quiet_window_ms: 0,
    trace: false,
  }) catch {
    err => abort(@debug.to_string(err))
  }
  assert_eq(result.status, AssertionFailed)
  assert_true(result.before is Some(_))
  assert_true(result.after is Some(after) && after.diagnostics == [])
  assert_true(
    result.differences.any(fn(value) { value.contains("missing diagnostic") }),
  )
  assert_eq(result.trace_path, None)
  @fs.rmdir(case_dir, recursive=true) catch {
    _ => ()
  }
}

///|
async test "runner discovers child cases in sorted order and keeps suite results serial" {
  let root = @fs.tmpdir(prefix="moon-lsp-compiletest-suite-test-")
  let explicit_order = ["zeta", "alpha"]
  explicit_order.sort_by(compare_case_entry)
  assert_eq(explicit_order, ["alpha", "zeta"])
  let _ = make_named_case(
    root, "zeta", "missing_symbol\n//~^ ERROR [E4021] \"mock unresolved\"\n", "let fixed = 1\n",
  )
  let _ = make_named_case(
    root, "alpha", "missing_symbol\n//~^ ERROR [E4021] \"mock unresolved\"\n", "let fixed = 1\n",
  )
  let discovered = discover_cases(root) catch {
    err => abort(@debug.to_string(err))
  }
  assert_eq([ for path in discovered => case_name(path) ], ["alpha", "zeta"])
  let results = run_suite([root], {
    server_command: mock_server_path(),
    timeout_ms: 1000,
    quiet_window_ms: 0,
    trace: false,
  }) catch {
    err => abort(@debug.to_string(err))
  }
  assert_eq([ for result in results => result.name ], ["alpha", "zeta"])
  assert_true(results.all(fn(result) { result.status == Passed }))
  @fs.rmdir(root, recursive=true) catch {
    _ => ()
  }
}

///|
test "reports preserve input order and stable summary counts" {
  let results : Array[@model.CaseResult] = [
    {
      name: "first",
      status: Passed,
      before: None,
      after: None,
      differences: [],
      trace_path: None,
      stderr_path: None,
    },
    {
      name: "second",
      status: AssertionFailed,
      before: None,
      after: None,
      differences: ["[before] missing diagnostic"],
      trace_path: None,
      stderr_path: None,
    },
  ]
  assert_eq(
    render_report(results),
    "PASS first\nFAIL second\n  [before] missing diagnostic\nsummary: passed=1 assertion-failed=1 infrastructure-failed=0\n",
  )
}
