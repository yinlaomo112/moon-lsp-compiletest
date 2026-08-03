///|
/// The marker grammar deliberately accepts only horizontal whitespace between
/// tokens. Source lines have already been split, so accepting a newline here
/// would hide a malformed marker rather than reporting its own line.
fn skip_whitespace(chars : Array[Char], start : Int) -> Int {
  let mut index = start
  while index < chars.length() && chars[index].is_ascii_whitespace() {
    index += 1
  }
  index
}

///|
fn is_marker_prefix(chars : Array[Char]) -> Bool {
  chars.length() >= 4 &&
  chars[0] == '/' &&
  chars[1] == '/' &&
  chars[2] == '~' &&
  chars[3] == '^'
}

///|
fn is_integer_code(chars : ArrayView[Char]) -> Bool {
  if chars.length() == 0 {
    false
  } else {
    let start = if chars[0] == '-' { 1 } else { 0 }
    if start == chars.length() {
      false
    } else {
      let mut index = start
      let mut valid = true
      while index < chars.length() {
        if !chars[index].is_ascii_digit() {
          valid = false
        }
        index += 1
      }
      valid
    }
  }
}

///|
fn severity_from_token(token : String) -> @model.Severity? {
  match token {
    "ERROR" => Some(Error)
    "WARNING" => Some(Warning)
    "INFORMATION" => Some(Information)
    "HINT" => Some(Hint)
    _ => None
  }
}
