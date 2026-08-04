///|
test "TEST-002 parses severities, code kinds, escaped literal, and shared anchor" {
  let source =
    #|let value = missing
    #|  //~^ ERROR [E4021] "unknown \"value\""
    #|  //~^ WARNING [42] "第二个"
    #|let next = value
    #|//~^ INFORMATION "note"
    #|//~^ HINT [lint.unused] "consider cleanup"
  let parsed = parse_expectations(source, Before)
  assert_eq(parsed.length(), 4)
  assert_eq(parsed[0].marker_line, 2)
  assert_eq(parsed[0].range.start.line, 0)
  assert_eq(parsed[1].range.start.line, 0)
  assert_eq(parsed[2].range.start.line, 3)
  assert_eq(parsed[0].severity, Error)
  assert_eq(parsed[1].severity, Warning)
  assert_eq(parsed[2].severity, Information)
  assert_eq(parsed[3].severity, Hint)
  assert_eq(parsed[0].code, Some(Text("E4021")))
  assert_eq(parsed[1].code, Some(Number(42)))
  assert_eq(parsed[3].code, Some(Text("lint.unused")))
  assert_eq(parsed[0].message_substring, "unknown \"value\"")
}

///|
test "TEST-002 preserves supplied stage and permits no marker expectations" {
  let no_expectations = parse_expectations("let fixed = 1\n", After)
  assert_eq(no_expectations, [])
  // An empty expectation list does not itself assert a diagnostic clear. The
  // session must first observe a target-URI publishDiagnostics [] notification.
  let parsed = parse_expectations(
    "let fixed = 1\n//~^ ERROR \"after only\"",
    After,
  )
  assert_eq(parsed[0].stage, After)
}

///|
fn assert_invalid_marker(source : String, expected_line : Int) -> Unit raise {
  try parse_expectations(source, Before) catch {
    InvalidMarker(line~, reason=_) => assert_eq(line, expected_line)
    InvalidRange(line~, reason=_) =>
      fail("unexpected InvalidRange at line \{line}")
  } noraise {
    _ => fail("expected marker parsing to fail")
  }
}

///|
test "TEST-002 rejects malformed grammar with the marker line" {
  assert_invalid_marker("//~^ ERROR \"first\"", 1)
  assert_invalid_marker("let a = 1\n//~^ []", 2)
  assert_invalid_marker("let a = 1\n//~^ERROR \"missing separator\"", 2)
  assert_invalid_marker("let a = 1\n//~^ ERROR", 2)
  assert_invalid_marker("let a = 1\n//~^ FATAL \"bad\"", 2)
  assert_invalid_marker("let a = 1\n//~^ ERROR [E4021 \"bad\"", 2)
  assert_invalid_marker("let a = 1\n//~^ ERROR [ ] \"bad\"", 2)
  assert_invalid_marker("let a = 1\n//~^ ERROR \"\"", 2)
  assert_invalid_marker("let a = 1\n//~^ ERROR \"bad\\q\"", 2)
  assert_invalid_marker("let a = 1\n//~^ ERROR \"unfinished", 2)
  assert_invalid_marker("let a = 1\n//~^ ERROR \"bad\" trailing", 2)
  let oversized = String::from_array(Array::make(8193, 'x'))
  assert_invalid_marker("let a = 1\n//~^ ERROR \"\{oversized}\"", 2)
}

///|
test "TEST-002 accepts leading whitespace and line-ending whitespace only" {
  let parsed = parse_expectations(
    "let a = 1\r\n\t//~^ HINT \"a\\tb\\n\"\r\n",
    Before,
  )
  assert_eq(parsed.length(), 1)
  assert_eq(parsed[0].message_substring, "a\tb\n")
}
