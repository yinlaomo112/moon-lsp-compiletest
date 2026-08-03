///|
test "TEST-001 preserves zero-based UTF-16 position and half-open range values" {
  let start : Position = { line: 1, character: 0 }
  // An astral code point occupies two UTF-16 code units, so character=2 is a
  // valid model value after one emoji. Position intentionally carries, rather
  // than recomputes, the negotiated LSP encoding offset.
  let end : Position = { line: 1, character: 2 }
  let range : Range = { start, end }
  assert_eq(range.start, start)
  assert_eq(range.end, end)
}

///|
test "TEST-001 retains LSP diagnostic code kind and missing severity" {
  let numeric : DiagnosticCode = Number(4021)
  let text : DiagnosticCode = Text("E4021")
  assert_true(numeric != text)
  let diagnostic : Diagnostic = {
    range: { start: { line: 0, character: 0 }, end: { line: 0, character: 1 } },
    severity: None,
    code: Some(text),
    source: None,
    message: "server omitted severity",
  }
  assert_eq(diagnostic.severity, None)
  assert_eq(diagnostic.code, Some(Text("E4021")))
}

///|
test "TEST-001 result records retain assertion and infrastructure distinction" {
  let failed : CaseResult = {
    name: "case",
    status: AssertionFailed,
    before: None,
    after: None,
    differences: ["message mismatch"],
    trace_path: Some("/tmp/trace.jsonl"),
    stderr_path: None,
  }
  assert_eq(failed.status, AssertionFailed)
  assert_eq(failed.differences, ["message mismatch"])
}

///|
test "TEST-001 public case values preserve stages, snapshots, and caller-owned arrays" {
  let before_source = "let 中文 = \"😀\"\nmissing\n"
  let after_source = "let 中文 = \"😀\"\nlet fixed = 1\n"
  let snapshot : DiagnosticSnapshot = {
    uri: "file:///tmp/%E4%B8%AD%E6%96%87.mbt",
    version: Some(3),
    diagnostics: [
      {
        range: {
          start: { line: 1, character: 0 },
          end: { line: 1, character: 7 },
        },
        severity: Some(Error),
        code: Some(Text("E4021")),
        source: Some("moonbit"),
        message: "unbound value",
      },
    ],
    unversioned: false,
  }
  let specification : CaseSpec = {
    name: "unicode-case",
    case_dir: "/tmp/unicode-case",
    before_source,
    after_source,
  }
  let options : RunOptions = {
    server_command: "moon-lsp",
    timeout_ms: 1000,
    quiet_window_ms: 50,
    trace: true,
  }
  assert_eq(specification.before_source, before_source)
  assert_eq(specification.after_source, after_source)
  assert_eq(snapshot.version, Some(3))
  assert_false(snapshot.unversioned)
  assert_eq(snapshot.diagnostics[0].range.end.character, 7)
  assert_eq(options.server_command, "moon-lsp")
}
