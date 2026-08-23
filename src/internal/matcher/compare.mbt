///|
fn severity_rank(severity : @model.Severity?) -> Int {
  match severity {
    None => 0
    Some(Error) => 1
    Some(Warning) => 2
    Some(Information) => 3
    Some(Hint) => 4
  }
}

///|
fn severity_name(severity : @model.Severity?) -> String {
  match severity {
    None => "<missing>"
    Some(Error) => "ERROR"
    Some(Warning) => "WARNING"
    Some(Information) => "INFORMATION"
    Some(Hint) => "HINT"
  }
}

///|
fn compare_code(
  left : @model.DiagnosticCode?,
  right : @model.DiagnosticCode?,
) -> Int {
  match left {
    None =>
      match right {
        None => 0
        Some(_) => -1
      }
    Some(left_code) =>
      match right {
        None => 1
        Some(Number(right_number)) =>
          match left_code {
            Number(left_number) => left_number.compare(right_number)
            Text(_) => 1
          }
        Some(Text(right_text)) =>
          match left_code {
            Number(_) => -1
            Text(left_text) => left_text.compare(right_text)
          }
      }
  }
}

///|
fn code_name(code : @model.DiagnosticCode?) -> String {
  match code {
    None => "<none>"
    Some(Number(value)) => "[\{value}]"
    Some(Text(value)) => "[\{value}]"
  }
}

///|
fn compare_position(left : @model.Position, right : @model.Position) -> Int {
  let line_order = left.line.compare(right.line)
  if line_order != 0 {
    line_order
  } else {
    left.character.compare(right.character)
  }
}

///|
fn compare_range(left : @model.Range, right : @model.Range) -> Int {
  let start_order = compare_position(left.start, right.start)
  if start_order != 0 {
    start_order
  } else {
    compare_position(left.end, right.end)
  }
}

///|
fn compare_diagnostic(
  left : @model.Diagnostic,
  right : @model.Diagnostic,
) -> Int {
  let range_order = compare_range(left.range, right.range)
  if range_order != 0 {
    range_order
  } else {
    let severity_order = severity_rank(left.severity).compare(
      severity_rank(right.severity),
    )
    if severity_order != 0 {
      severity_order
    } else {
      let code_order = compare_code(left.code, right.code)
      if code_order != 0 {
        code_order
      } else {
        let message_order = left.message.compare(right.message)
        if message_order != 0 {
          message_order
        } else {
          match left.source {
            None =>
              match right.source {
                None => 0
                Some(_) => -1
              }
            Some(left_source) =>
              match right.source {
                None => 1
                Some(right_source) => left_source.compare(right_source)
              }
          }
        }
      }
    }
  }
}

///|
fn compare_expectation(
  left : @model.Expectation,
  right : @model.Expectation,
) -> Int {
  let range_order = compare_range(left.range, right.range)
  if range_order != 0 {
    range_order
  } else {
    let severity_order = severity_rank(Some(left.severity)).compare(
      severity_rank(Some(right.severity)),
    )
    if severity_order != 0 {
      severity_order
    } else {
      let code_order = compare_code(left.code, right.code)
      if code_order != 0 {
        code_order
      } else {
        let message_order = left.message_substring.compare(
          right.message_substring,
        )
        if message_order != 0 {
          message_order
        } else {
          left.marker_line.compare(right.marker_line)
        }
      }
    }
  }
}

///|
fn code_matches(
  expected : @model.DiagnosticCode?,
  actual : @model.DiagnosticCode?,
) -> Bool {
  match expected {
    None => true
    Some(expected_code) =>
      actual is Some(actual_code) && expected_code == actual_code
  }
}

///|
/// Markers have no column syntax. Their zero-width range anchors a diagnostic
/// to a source line, while the diagnostic itself retains its full LSP range.
fn matches(
  expectation : @model.Expectation,
  diagnostic : @model.Diagnostic,
) -> Bool {
  expectation.range.start.line == diagnostic.range.start.line &&
  diagnostic.severity is Some(actual_severity) &&
  actual_severity == expectation.severity &&
  code_matches(expectation.code, diagnostic.code) &&
  diagnostic.message.contains(expectation.message_substring)
}

///|
fn augment(
  expectation_index : Int,
  candidates : Array[Array[Bool]],
  seen_actual : Array[Bool],
  actual_assignment : Array[Int],
) -> Bool {
  let mut actual_index = 0
  while actual_index < actual_assignment.length() {
    if candidates[expectation_index][actual_index] && !seen_actual[actual_index] {
      seen_actual[actual_index] = true
      if actual_assignment[actual_index] == -1 ||
        augment(
          actual_assignment[actual_index],
          candidates,
          seen_actual,
          actual_assignment,
        ) {
        actual_assignment[actual_index] = expectation_index
        return true
      }
    }
    actual_index += 1
  }
  false
}

///|
fn describe_expectation(expectation : @model.Expectation) -> String {
  "marker line \{expectation.marker_line}: line \{expectation.range.start.line}, \{severity_name(Some(expectation.severity))} \{code_name(expectation.code)} containing \{repr(expectation.message_substring)}"
}

///|
fn describe_diagnostic(diagnostic : @model.Diagnostic) -> String {
  "line \{diagnostic.range.start.line}: \{severity_name(diagnostic.severity)} \{code_name(diagnostic.code)} message \{repr(diagnostic.message)}"
}

///|
fn mismatch_count(
  expectation : @model.Expectation,
  diagnostic : @model.Diagnostic,
) -> Int {
  let mut count = 0
  if expectation.range.start.line != diagnostic.range.start.line {
    count += 1
  }
  if diagnostic.severity != Some(expectation.severity) {
    count += 1
  }
  if !code_matches(expectation.code, diagnostic.code) {
    count += 1
  }
  if !diagnostic.message.contains(expectation.message_substring) {
    count += 1
  }
  count
}

///|
fn append_field_differences(
  differences : Array[String],
  expectation : @model.Expectation,
  diagnostic : @model.Diagnostic,
) -> Unit {
  let prefix = "candidate for marker line \{expectation.marker_line}"
  if expectation.range.start.line != diagnostic.range.start.line {
    differences.push(
      "\{prefix}: start line expected \{expectation.range.start.line}, got \{diagnostic.range.start.line}",
    )
  }
  if diagnostic.severity != Some(expectation.severity) {
    differences.push(
      "\{prefix}: severity expected \{severity_name(Some(expectation.severity))}, got \{severity_name(diagnostic.severity)}",
    )
  }
  if !code_matches(expectation.code, diagnostic.code) {
    differences.push(
      "\{prefix}: code expected \{code_name(expectation.code)}, got \{code_name(diagnostic.code)}",
    )
  }
  if !diagnostic.message.contains(expectation.message_substring) {
    differences.push(
      "\{prefix}: message expected substring \{repr(expectation.message_substring)}, got \{repr(diagnostic.message)}",
    )
  }
}

///|
fn nearest_diagnostic(
  expectation : @model.Expectation,
  diagnostics : Array[@model.Diagnostic],
) -> @model.Diagnostic? {
  let mut best : @model.Diagnostic? = None
  let mut best_count = 5
  for diagnostic in diagnostics {
    let candidate_count = mismatch_count(expectation, diagnostic)
    if candidate_count < best_count {
      best = Some(diagnostic)
      best_count = candidate_count
    }
  }
  best
}

///|
/// Exhaustively and deterministically match expectations against diagnostics.
///
/// The maximum matching step prevents a broad expectation from consuming the
/// sole diagnostic required by a more specific expectation. Empty arrays match
/// here as a pure value comparison; session is responsible for requiring an
/// explicit publishDiagnostics [] notification before it invokes this function
/// for an empty stage.
pub fn compare(
  expectations : ArrayView[@model.Expectation],
  actual : ArrayView[@model.Diagnostic],
) -> MatchReport {
  let normalized_expectations = expectations.to_owned()
  let normalized_actual = actual.to_owned()
  normalized_expectations.sort_by(compare_expectation)
  normalized_actual.sort_by(compare_diagnostic)

  let candidates : Array[Array[Bool]] = []
  for expectation in normalized_expectations {
    let row : Array[Bool] = []
    for diagnostic in normalized_actual {
      row.push(matches(expectation, diagnostic))
    }
    candidates.push(row)
  }

  let actual_assignment = Array::make(normalized_actual.length(), -1)
  let mut expectation_index = 0
  while expectation_index < normalized_expectations.length() {
    let seen_actual = Array::make(normalized_actual.length(), false)
    ignore(
      augment(expectation_index, candidates, seen_actual, actual_assignment),
    )
    expectation_index += 1
  }

  let matched_expectations = Array::make(
    normalized_expectations.length(),
    false,
  )
  for assigned in actual_assignment {
    if assigned != -1 {
      matched_expectations[assigned] = true
    }
  }

  let missing : Array[@model.Expectation] = []
  let differences : Array[String] = []
  let mut index = 0
  while index < normalized_expectations.length() {
    if !matched_expectations[index] {
      let expectation = normalized_expectations[index]
      missing.push(expectation)
      differences.push(
        "missing diagnostic: \{describe_expectation(expectation)}",
      )
      match nearest_diagnostic(expectation, normalized_actual) {
        None => ()
        Some(diagnostic) =>
          append_field_differences(differences, expectation, diagnostic)
      }
    }
    index += 1
  }

  let extra : Array[@model.Diagnostic] = []
  let mut actual_index = 0
  while actual_index < normalized_actual.length() {
    if actual_assignment[actual_index] == -1 {
      let diagnostic = normalized_actual[actual_index]
      extra.push(diagnostic)
      differences.push("extra diagnostic: \{describe_diagnostic(diagnostic)}")
    }
    actual_index += 1
  }
  {
    passed: missing.length() == 0 && extra.length() == 0,
    missing,
    extra,
    differences,
  }
}
