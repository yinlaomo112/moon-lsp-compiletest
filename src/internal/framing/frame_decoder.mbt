///|
/// Incremental decoder for fragmented and coalesced LSP stdio frames.
///
/// Header buffering is deliberately bounded independently from the payload
/// limit.  A peer that never sends the terminating CRLF sequence must not be
/// able to grow an otherwise idle session without limit.
let maximum_header_bytes : Int = 16_384

///|
pub struct FrameDecoder {
  max_content_length : Int
  mut buffer : Array[Byte]
}

///|
/// Make a decoder that rejects bodies larger than `max_content_length` bytes.
pub fn FrameDecoder::new(max_content_length~ : Int) -> FrameDecoder {
  {
    max_content_length: if max_content_length < 0 {
      0
    } else {
      max_content_length
    },
    buffer: [],
  }
}

///|
/// Encode a UTF-8 JSON payload using an ASCII `Content-Length` header.
pub fn encode_frame(payload : String) -> Bytes {
  let body = @utf8.encode(payload)
  let header = @utf8.encode("Content-Length: \{body.length()}\r\n\r\n")
  header + body
}

///|
/// Feed an arbitrary stdout chunk and return every complete JSON payload in it.
pub fn FrameDecoder::feed(
  self : FrameDecoder,
  chunk : BytesView,
) -> Array[String] raise FramingError {
  for byte in chunk {
    self.buffer.push(byte)
  }
  let payloads = []
  let mut continue_decoding = true
  while continue_decoding {
    match find_header_end(self.buffer) {
      None => {
        if self.buffer.length() > maximum_header_bytes {
          raise HeaderTooLarge(
            actual=self.buffer.length(),
            limit=maximum_header_bytes,
          )
        }
        continue_decoding = false
      }
      Some(header_end) => {
        if header_end > maximum_header_bytes {
          raise HeaderTooLarge(actual=header_end, limit=maximum_header_bytes)
        }
        let content_length = parse_headers(
          self.buffer[:header_end],
          limit=self.max_content_length,
        )
        let body_start = header_end + 4
        if self.buffer.length() < body_start + content_length {
          continue_decoding = false
        } else {
          let body = Bytes::from_array(
            self.buffer[body_start:body_start + content_length],
          )
          let payload = decode_payload(body)
          payloads.push(payload)
          self.buffer = self.buffer[body_start + content_length:].to_owned()
        }
      }
    }
  }
  payloads
}

///|
/// Report an incomplete header or body at end of stream.
pub fn FrameDecoder::finish(self : FrameDecoder) -> Unit raise FramingError {
  if !self.buffer.is_empty() {
    raise UnexpectedEof
  }
}

///|
fn find_header_end(bytes : Array[Byte]) -> Int? {
  let mut found = None
  for index in 0..<bytes.length() {
    if found is None &&
      index + 3 < bytes.length() &&
      bytes[index] == b'\r' &&
      bytes[index + 1] == b'\n' &&
      bytes[index + 2] == b'\r' &&
      bytes[index + 3] == b'\n' {
      found = Some(index)
    }
  }
  found
}

///|
fn parse_headers(
  header_bytes : ArrayView[Byte],
  limit~ : Int,
) -> Int raise FramingError {
  let header = decode_payload(Bytes::from_array(header_bytes))
  let mut content_length : Int? = None
  for raw_line in header.split("\r\n") {
    let line = raw_line.to_owned()
    match line.split_once(":") {
      None => raise InvalidHeader(reason="header has no colon")
      Some((name, value)) => {
        let name_text = name.to_owned().trim().to_owned()
        if name_text.is_empty() {
          raise InvalidHeader(reason="header name is empty")
        }
        if name_text.to_lower() == "content-length" {
          match content_length {
            Some(_) => raise DuplicateContentLength
            None => {
              let text = value.trim().to_owned()
              let value = parse_decimal(text)
              content_length = Some(value)
            }
          }
        }
      }
    }
  }
  match content_length {
    None => raise MissingContentLength
    Some(value) => {
      if value > limit {
        raise ContentTooLarge(actual=value, limit~)
      }
      value
    }
  }
}

///|
fn parse_decimal(text : String) -> Int raise FramingError {
  if text.is_empty() {
    raise InvalidContentLength(value=text)
  }
  let mut value = 0
  for char in text {
    if !char.is_ascii_digit() || value > 214748364 {
      raise InvalidContentLength(value=text)
    }
    let digit = char.to_int() - '0'.to_int()
    if value == 214748364 && digit > 7 {
      raise InvalidContentLength(value=text)
    }
    value = value * 10 + digit
  }
  value
}

///|
fn decode_payload(bytes : Bytes) -> String raise FramingError {
  @utf8.decode(bytes) catch {
    _ => raise InvalidUtf8
  }
}
