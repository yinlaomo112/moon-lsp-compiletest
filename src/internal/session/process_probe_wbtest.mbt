///|
async test "native orphan process streams remain usable" {
  let (stdin, writer) = @process.write_to_process()
  let (reader, stdout) = @process.read_from_process()
  let pid = @process.spawn_orphan(
    "/bin/sh",
    ["-c", "read line; printf '%s\n' \"$line\""],
    stdin~,
    stdout~,
  )
  writer.write("ready\n")
  writer.close()
  assert_eq(reader.read_until("\n"), Some("ready"))
  assert_eq(@process.wait_pid(pid), 0)
}

///|
async test "timing out a native read leaves the stream usable" {
  let (stdin, writer) = @process.write_to_process()
  let (reader, stdout) = @process.read_from_process()
  let pid = @process.spawn_orphan(
    "/bin/sh",
    ["-c", "sleep 0.08; printf 'delayed\\n'"],
    stdin~,
    stdout~,
  )
  writer.close()
  assert_eq(@async.with_timeout_opt(10, () => reader.read_until("\n")), None)
  assert_eq(reader.read_until("\n"), Some("delayed"))
  assert_eq(@process.wait_pid(pid), 0)
}
