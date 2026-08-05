///|
/// Invalid or incomplete LSP stdio frame.
pub(all) suberror FramingError {
  MissingContentLength
  DuplicateContentLength
  InvalidContentLength(value~ : String)
  HeaderTooLarge(actual~ : Int, limit~ : Int)
  ContentTooLarge(actual~ : Int, limit~ : Int)
  InvalidHeader(reason~ : String)
  InvalidUtf8
  UnexpectedEof
} derive(Debug, Eq)
