///|
test "mock scenario parser is closed over the documented names" {
  assert_eq(parse_scenario("normal"), Some(Normal))
  assert_eq(parse_scenario("multi-uri"), Some(MultiUri))
  assert_eq(parse_scenario("stderr-flood"), Some(StderrFlood))
  assert_eq(parse_scenario("partial-frame"), Some(PartialFrame))
  assert_eq(parse_scenario("early-exit"), Some(EarlyExit))
  assert_eq(parse_scenario("timeout"), Some(Timeout))
  assert_eq(parse_scenario("id-collision"), Some(IdCollision))
  assert_eq(parse_scenario("anything-else"), None)
}

///|
test "mock initialize response advertises incremental sync" {
  let response = initialize_response(Number(7))
  assert_true(response.contains("\"textDocumentSync\":2"))
  assert_true(response.contains("\"id\":7"))
}

///|
test "mock diagnostic transition has a real error then an explicit empty list" {
  let nonempty = target_diagnostics("file:///tmp/mock.mbt", clear=false)
  let cleared = target_diagnostics("file:///tmp/mock.mbt", clear=true)
  assert_true(nonempty.contains("E4021"))
  assert_true(nonempty.contains("mock unresolved name"))
  assert_true(cleared.contains("\"diagnostics\":[]"))
}
