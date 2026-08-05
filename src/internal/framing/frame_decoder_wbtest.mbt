///|
test "framing accepts fragmented UTF-8 payloads using byte Content-Length" {
  let payload = "{\"message\":\"你好\"}"
  let encoded = encode_frame(payload)
  let decoder = FrameDecoder::new(max_content_length=1024)
  let cut = 11
  assert_eq(decoder.feed(encoded[:cut]), [])
  assert_eq(decoder.feed(encoded[cut:]), [payload])
  decoder.finish()
  assert_eq(
    encode_frame("你好"),
    @utf8.encode("Content-Length: 6\r\n\r\n你好"),
  )
}

///|
test "framing emits every coalesced payload and preserves the tail" {
  let decoder = FrameDecoder::new(max_content_length=1024)
  let coalesced = encode_frame("{\"id\":1}") + encode_frame("{\"id\":2}")
  assert_eq(decoder.feed(coalesced), ["{\"id\":1}", "{\"id\":2}"])
  decoder.finish()
}

///|
test "framing accepts every one-cut split through a UTF-8 header and body" {
  let payload = "{\"message\":\"中文 😀\",\"id\":7}"
  let frame = encode_frame(payload)
  for cut in 0..<=frame.length() {
    let decoder = FrameDecoder::new(max_content_length=1024)
    let decoded = decoder.feed(frame[:cut])
    for value in decoder.feed(frame[cut:]) {
      decoded.push(value)
    }
    assert_eq(decoded, [payload])
    decoder.finish()
  }
}

///|
test "framing rejects invalid decimal values and malformed header fields" {
  let invalid_values = ["", "-1", "+1", "1.5", "  ", "2147483648"]
  for value in invalid_values {
    let decoder = FrameDecoder::new(max_content_length=1024)
    let rejected = try
      decoder.feed(@utf8.encode("Content-Length: \{value}\r\n\r\n"))
    catch {
      InvalidContentLength(value=_) => true
      _ => false
    } noraise {
      _ => false
    }
    assert_true(rejected)
  }
  let no_colon = FrameDecoder::new(max_content_length=1024)
  let no_colon_rejected = try
    no_colon.feed(b"Content-Length: 0\r\nbroken-header\r\n\r\n")
  catch {
    InvalidHeader(reason=_) => true
    _ => false
  } noraise {
    _ => false
  }
  assert_true(no_colon_rejected)
}

///|
test "framing rejects malformed, oversized, and invalid UTF-8 frames" {
  let missing = FrameDecoder::new(max_content_length=32)
  let missing_raised = try
    missing.feed(b"Content-Type: application/vscode-jsonrpc\r\n\r\n{}")
  catch {
    MissingContentLength => true
    _ => false
  } noraise {
    _ => false
  }
  assert_true(missing_raised)

  let duplicate = FrameDecoder::new(max_content_length=32)
  let duplicate_raised = try
    duplicate.feed(b"Content-Length: 2\r\ncontent-length: 2\r\n\r\n{}")
  catch {
    DuplicateContentLength => true
    _ => false
  } noraise {
    _ => false
  }
  assert_true(duplicate_raised)

  let oversized = FrameDecoder::new(max_content_length=1)
  let oversized_raised = try
    oversized.feed(b"Content-Length: 2\r\n\r\n{}")
  catch {
    ContentTooLarge(actual=2, limit=1) => true
    _ => false
  } noraise {
    _ => false
  }
  assert_true(oversized_raised)

  let invalid_utf8 = FrameDecoder::new(max_content_length=1)
  let invalid_utf8_raised = try
    invalid_utf8.feed([
      b'C', b'o', b'n', b't', b'e', b'n', b't', b'-', b'L', b'e', b'n', b'g', b't',
      b'h', b':', b' ', b'1', b'\r', b'\n', b'\r', b'\n', 0xFF,
    ])
  catch {
    InvalidUtf8 => true
    _ => false
  } noraise {
    _ => false
  }
  assert_true(invalid_utf8_raised)
}

///|
test "framing bounds an unterminated or oversized header" {
  let unterminated = FrameDecoder::new(max_content_length=1024)
  let too_long = Array::make(maximum_header_bytes + 1, b'x')
  let unterminated_raised = try
    unterminated.feed(Bytes::from_array(too_long))
  catch {
    HeaderTooLarge(actual~, limit~) =>
      actual == maximum_header_bytes + 1 && limit == maximum_header_bytes
    _ => false
  } noraise {
    _ => false
  }
  assert_true(unterminated_raised)

  let oversized = FrameDecoder::new(max_content_length=1024)
  let long_name = "x".repeat(maximum_header_bytes + 1)
  let oversized_raised = try
    oversized.feed(@utf8.encode("\{long_name}: 0\r\n\r\n"))
  catch {
    HeaderTooLarge(actual=_, limit~) => limit == maximum_header_bytes
    _ => false
  } noraise {
    _ => false
  }
  assert_true(oversized_raised)
}

///|
test "framing finish exposes a truncated frame" {
  let decoder = FrameDecoder::new(max_content_length=32)
  assert_eq(decoder.feed(b"Content-Length: 3\r\n\r\n{}"), [])
  let truncated = try decoder.finish() catch {
    UnexpectedEof => true
    _ => false
  } noraise {
    _ => false
  }
  assert_true(truncated)
}
