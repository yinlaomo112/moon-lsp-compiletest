///|
/// JSON-RPC request identifier.
pub(all) enum RequestId {
  Number(Int)
  Text(String)
} derive(Debug, Eq)

///|
/// Classification must inspect `method` before correlating an `id`.
pub(all) enum MessageKind {
  ServerRequest(RequestId, String)
  Notification(String)
  Response(RequestId)
} derive(Debug, Eq)

///|
pub(all) suberror ProtocolError {
  InvalidJson(reason~ : String)
  InvalidMessage(reason~ : String)
  UnsupportedCapability(reason~ : String)
  InvalidDiagnostic(reason~ : String)
  InvalidFileUri(reason~ : String)
} derive(Debug, Eq)
