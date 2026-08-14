pub fn probe() -> Unit {
  let 中文变量 = "😀"
  missing_unicode_symbol
  //~^ ERROR [E4021] "unbound"
  let _ = 中文变量
}
