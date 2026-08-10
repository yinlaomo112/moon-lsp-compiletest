///|
fn expectation(
  line : Int,
  severity : @model.Severity,
  code : @model.DiagnosticCode?,
  message : String,
  marker_line? : Int = 1,
) -> @model.Expectation {
  {
    stage: Before,
    range: { start: { line, character: 0 }, end: { line, character: 0 } },
    severity,
    code,
    message_substring: message,
    marker_line,
  }
}

///|
fn diagnostic(
  line : Int,
  severity : @model.Severity?,
  code : @model.DiagnosticCode?,
  message : String,
  character? : Int = 0,
) -> @model.Diagnostic {
  {
    range: {
      start: { line, character },
      end: { line, character: character + 1 },
    },
    severity,
    code,
    source: None,
    message,
  }
}

///|
test "TEST-005 matches independent of notification order" {
  let expected = [
    expectation(0, Error, Some(Text("E1")), "alpha", marker_line=2),
    expectation(2, Warning, Some(Number(7)), "beta", marker_line=4),
  ]
  let alpha = diagnostic(
    0,
    Some(Error),
    Some(Text("E1")),
    "alpha detail",
    character=8,
  )
  let beta = diagnostic(2, Some(Warning), Some(Number(7)), "beta detail")
  let forward = compare(expected, [alpha, beta])
  let reversed = compare(expected, [beta, alpha])
  assert_true(forward.passed)
  assert_eq(forward, reversed)
}

///|
test "TEST-005 uses maximum matching instead of greedy consumption" {
  let broad = expectation(0, Error, None, "alpha", marker_line=2)
  let specific = expectation(0, Error, Some(Text("E1")), "alpha", marker_line=3)
  let code_one = diagnostic(0, Some(Error), Some(Text("E1")), "alpha")
  let code_two = diagnostic(0, Some(Error), Some(Text("E2")), "alpha")
  let report = compare([broad, specific], [code_one, code_two])
  assert_true(report.passed)
  assert_eq(report.differences, [])
}

///|
test "TEST-005 distinguishes missing, field mismatch, and duplicate extra" {
  let expected = expectation(
    3,
    Error,
    Some(Text("E4021")),
    "unbound value",
    marker_line=5,
  )
  let wrong = diagnostic(3, Some(Warning), Some(Text("E7")), "different")
  let duplicate = diagnostic(3, Some(Warning), Some(Text("E7")), "different")
  let report = compare([expected], [duplicate, wrong])
  assert_false(report.passed)
  assert_eq(report.missing, [expected])
  assert_eq(report.extra.length(), 2)
  assert_eq(report.differences, [
    "missing diagnostic: marker line 5: line 3, ERROR [E4021] containing \"unbound value\"",
    "candidate for marker line 5: severity expected ERROR, got WARNING", "candidate for marker line 5: code expected [E4021], got [E7]",
    "candidate for marker line 5: message expected substring \"unbound value\", got \"different\"",
    "extra diagnostic: line 3: WARNING [E7] message \"different\"", "extra diagnostic: line 3: WARNING [E7] message \"different\"",
  ])
}

///|
test "TEST-005 anchors range at the marker source line" {
  let expected = expectation(1, Information, None, "note")
  let report = compare([expected], [
    diagnostic(1, Some(Information), None, "note", character=12),
  ])
  assert_true(report.passed)
  let wrong_line = compare([expected], [
    diagnostic(2, Some(Information), None, "note"),
  ])
  assert_false(wrong_line.passed)
  assert_true(
    wrong_line.differences[1].contains("start line expected 1, got 2"),
  )
}

///|
test "TEST-005 compares empty arrays only after the session's explicit-clear barrier" {
  let report = compare([], [])
  assert_true(report.passed)
  assert_eq(report.missing, [])
  assert_eq(report.extra, [])
}

///|
test "TEST-005 keeps complete three-diagnostic matching deterministic across permutations" {
  let expected = [
    expectation(0, Error, Some(Text("E1")), "alpha", marker_line=2),
    expectation(1, Warning, Some(Number(7)), "beta", marker_line=4),
    expectation(2, Hint, None, "gamma", marker_line=6),
  ]
  let alpha = diagnostic(0, Some(Error), Some(Text("E1")), "alpha detail")
  let beta = diagnostic(1, Some(Warning), Some(Number(7)), "beta detail")
  let gamma = diagnostic(2, Some(Hint), Some(Text("other")), "gamma detail")
  let permutations : Array[Array[@model.Diagnostic]] = [
    [alpha, beta, gamma],
    [alpha, gamma, beta],
    [beta, alpha, gamma],
    [beta, gamma, alpha],
    [gamma, alpha, beta],
    [gamma, beta, alpha],
  ]
  let baseline = compare(expected, permutations[0])
  assert_true(baseline.passed)
  for actual in permutations {
    assert_eq(compare(expected, actual), baseline)
  }
}

///|
test "TEST-005 permits an omitted expected code but still rejects an omitted severity" {
  let broad_code = expectation(0, Error, None, "message")
  let actual_with_code = diagnostic(
    0,
    Some(Error),
    Some(Number(4021)),
    "message with code",
  )
  assert_true(compare([broad_code], [actual_with_code]).passed)

  let missing_severity = diagnostic(
    0,
    None,
    Some(Number(4021)),
    "message with code",
  )
  let report = compare([broad_code], [missing_severity])
  assert_false(report.passed)
  assert_true(
    report.differences.any(fn(value) {
      value.contains("severity expected ERROR")
    }),
  )
}
