///|
/// Marker syntax or source-location failure.
pub(all) suberror MarkerError {
  InvalidMarker(line~ : Int, reason~ : String)
  InvalidRange(line~ : Int, reason~ : String)
} derive(Debug, Eq)
