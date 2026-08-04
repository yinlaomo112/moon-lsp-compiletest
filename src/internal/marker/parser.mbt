///|
let maximum_marker_characters : Int = 8192

///|
fn invalid_marker(line : Int, reason : String) -> Unit raise MarkerError {
  raise InvalidMarker(line~, reason~)
}

///|
fn numeric_code(value : Int) -> @model.DiagnosticCode {
  Number(value)
}

///|
fn text_code(value : String) -> @model.DiagnosticCode {
  Text(value)
}

///|
fn parse_code(
  chars : Array[Char],
  open_bracket : Int,
  line : Int,
) -> (@model.DiagnosticCode, Int) raise MarkerError {
  let mut index = open_bracket + 1
  while index < chars.length() && chars[index] != ']' {
    if chars[index].is_ascii_whitespace() || chars[index] == '[' {
      invalid_marker(line, "code must not contain whitespace or '['")
    }
    index += 1
  }
  if index == chars.length() {
    invalid_marker(line, "unterminated diagnostic code")
  }
  if index == open_bracket + 1 {
    invalid_marker(line, "diagnostic code must not be empty")
  }
  let raw = String::from_array(chars[open_bracket + 1:index])
  let code = if is_integer_code(chars[open_bracket + 1:index]) {
    let value : Int = @strconv.from_str(raw) catch {
      _ =>
        raise InvalidMarker(
          line~,
          reason="numeric diagnostic code is out of range",
        )
    }
    numeric_code(value)
  } else {
    text_code(raw)
  }
  (code, index + 1)
}

///|
fn parse_quoted_message(
  chars : Array[Char],
  quote : Int,
  line : Int,
) -> (String, Int) raise MarkerError {
  let mut index = quote + 1
  let decoded : Array[Char] = []
  let mut closed = false
  while index < chars.length() && !closed {
    match chars[index] {
      '"' => {
        closed = true
        index += 1
      }
      '\\' => {
        if index + 1 == chars.length() {
          invalid_marker(line, "unfinished escape in message")
        }
        let escaped = chars[index + 1]
        match escaped {
          '"' => decoded.push('"')
          '\\' => decoded.push('\\')
          'n' => decoded.push('\n')
          'r' => decoded.push('\r')
          't' => decoded.push('\t')
          _ => invalid_marker(line, "unsupported escape in message")
        }
        index += 2
      }
      character => {
        decoded.push(character)
        index += 1
      }
    }
  }
  if !closed {
    invalid_marker(line, "unterminated quoted message")
  }
  if decoded.length() == 0 {
    invalid_marker(line, "message substring must not be empty")
  }
  (String::from_array(decoded), index)
}

///|
fn parse_marker_line(
  text : StringView,
  stage : @model.Stage,
  marker_line : Int,
  target_line : Int,
) -> @model.Expectation raise MarkerError {
  let chars = text.to_array()
  if chars.length() > maximum_marker_characters {
    invalid_marker(marker_line, "marker exceeds 8192 characters")
  }
  if !is_marker_prefix(chars) {
    invalid_marker(marker_line, "marker must begin with //~^")
  }
  let after_prefix = skip_whitespace(chars, 4)
  if after_prefix == 4 {
    invalid_marker(marker_line, "expected whitespace after //~^")
  }
  let mut token_end = after_prefix
  while token_end < chars.length() && chars[token_end].is_ascii_alphabetic() {
    token_end += 1
  }
  if token_end == after_prefix {
    invalid_marker(marker_line, "expected severity")
  }
  let severity_token = String::from_array(chars[after_prefix:token_end])
  let severity = match severity_from_token(severity_token) {
    Some(value) => value
    None =>
      raise InvalidMarker(
        line=marker_line,
        reason="unknown severity '\{severity_token}'",
      )
  }
  let after_severity = skip_whitespace(chars, token_end)
  if after_severity == token_end {
    invalid_marker(marker_line, "expected whitespace before message")
  }
  let (code, after_code) = if after_severity < chars.length() &&
    chars[after_severity] == '[' {
    let (parsed, after) = parse_code(chars, after_severity, marker_line)
    let after_space = skip_whitespace(chars, after)
    if after_space == after {
      invalid_marker(marker_line, "expected whitespace after diagnostic code")
    }
    (Some(parsed), after_space)
  } else {
    (None, after_severity)
  }
  if after_code == chars.length() || chars[after_code] != '"' {
    invalid_marker(marker_line, "expected quoted message")
  }
  let (message, after_message) = parse_quoted_message(
    chars, after_code, marker_line,
  )
  if skip_whitespace(chars, after_message) != chars.length() {
    invalid_marker(
      marker_line, "unexpected trailing token after quoted message",
    )
  }
  {
    stage,
    range: {
      start: { line: target_line, character: 0 },
      end: { line: target_line, character: 0 },
    },
    severity,
    code,
    message_substring: message,
    marker_line,
  }
}

///|
/// Parse strict `//~^ SEVERITY [CODE] "literal substring"` expectations.
///
/// The marker owns no source span syntax. Its zero-width range is an anchor at
/// the beginning of the most recent non-marker line; matcher therefore uses
/// the anchor's line as the positional constraint. Consecutive markers share
/// that same source line, which permits multiple expected diagnostics there.
pub fn parse_expectations(
  source : String,
  stage : @model.Stage,
) -> Array[@model.Expectation] raise MarkerError {
  let expectations : Array[@model.Expectation] = []
  let mut marker_line = 1
  let mut last_source_line : Int? = None
  for raw_line in source.split("\n") {
    let trimmed = raw_line.trim_start()
    let chars = trimmed.to_array()
    if is_marker_prefix(chars) {
      let target_line = match last_source_line {
        Some(value) => value
        None =>
          raise InvalidMarker(
            line=marker_line,
            reason="//~^ cannot appear before a source line",
          )
      }
      expectations.push(
        parse_marker_line(trimmed, stage, marker_line, target_line),
      )
    } else {
      last_source_line = Some(marker_line - 1)
    }
    marker_line += 1
  }
  expectations
}
