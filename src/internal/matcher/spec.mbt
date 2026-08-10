///|
/// Exhaustive one-to-one comparison result.
pub(all) struct MatchReport {
  passed : Bool
  missing : Array[@model.Expectation]
  extra : Array[@model.Diagnostic]
  differences : Array[String]
} derive(Debug, Eq)
