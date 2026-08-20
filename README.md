# moon-lsp-compiletest

面向 MoonBit 的 LSP 诊断回归测试工具。它以 compiletest 风格的源码内联断言，
通过真实 `moon-lsp --stdio` 验证一个文件从 `before.mbt` 到 `after.mbt` 的
`publishDiagnostics`。

首版是一个窄工具：只测试单文件、两个修订、push diagnostics；它不是通用 LSP
框架，也不覆盖 completion、hover、definition、YAML 场景或 `--bless`。

## 已验证能力

- 独立临时 MoonBit module 与独立 `moon-lsp` 进程；不修改用户工作区。
- 严格 `//~^` marker、UTF-8 Content-Length framing、file URI、目标 URI 过滤。
- 无序的一一诊断匹配：位置、严重度、可选错误码和消息子串。
- before/after 全文文档更新、显式空 diagnostics 清除验证、trace 和 0/1/2 退出码。
- Mock 故障路径及真实 `moon-lsp v0.10.4` 的 3 个端到端用例。

## 前置条件

Linux native、`moon` 与 `moon-lsp` 在 `PATH`。本次验证使用：

```text
moon 0.1.20260713
moonc / moon-lsp v0.10.4+2cc641edf
moonbitlang/async 0.20.3
```

## 快速开始

```bash
moon build --target native --warn-list +73 --deny-warn
_build/native/debug/build/cmd/moon-lsp-compiletest/moon-lsp-compiletest.exe \
  --server moon-lsp --timeout-ms 7000 --quiet-window-ms 100 tests/cases
```

预期摘要：

```text
PASS multi-diagnostic
PASS unbound-to-fixed
PASS unicode-range
summary: passed=3 assertion-failed=0 infrastructure-failed=0
```

也可以执行完整本地验收：

```bash
bash scripts/acceptance.sh
```

该脚本先运行纯 package 的 `--target all` check/build/test，再运行 Linux native
CLI、mock 和真实 `moon-lsp` 互操作门禁。

## 示例

`tests/cases/unbound-to-fixed` 是最小示例：before 断言 E4021，after 修复标识符且
只接受 server 推送的显式空诊断数组。

## 用例格式

每个用例目录必须有两份文件：

```text
case-name/
├── before.mbt
└── after.mbt
```

`before.mbt` 或 `after.mbt` 的下一行 marker 描述上一源码行的期望：

```moonbit
pub fn probe() -> Unit {
  missing_symbol
  //~^ ERROR [E4021] "unbound"
}
```

语法为：

```text
//~^ SEVERITY [OPTIONAL_CODE] "literal message substring"
```

`SEVERITY` 可为 `ERROR`、`WARNING`、`INFORMATION` 或 `HINT`；错误码可省略，
支持字符串或数字。空 `after.mbt` 期望只会在 server 明确推送目标 URI 的空
`diagnostics` 数组时通过。

## CLI

```text
moon-lsp-compiletest [--server PATH] [--timeout-ms N]
                     [--quiet-window-ms N] [--trace] CASE_DIR...
```

- `0`：全部匹配；`1`：断言不匹配；`2`：参数、进程或协议基础设施失败。
- `--trace` 在成功时保留每 case 的 JSON-RPC trace；基础设施失败总会保留 trace
  与 server stderr 路径。
- case 按输入顺序串行运行。

要查看断言失败格式：

```bash
_build/native/debug/build/cmd/moon-lsp-compiletest/moon-lsp-compiletest.exe \
  --server moon-lsp tests/failure-cases/message-mismatch
```

## `moon-lsp` 互操作说明

当前 native `moon-lsp` 会读取临时 module 的 `_build/packages.json`。runner 在
启动 LSP 前运行一次隔离的 `moon check --target native` 来生成该索引；before
源码带诊断时该检查的非零退出是预期行为，其输出会保存在临时工作区而不会混入 CLI
摘要。LSP 仍然是唯一被断言的诊断来源。

server 宣告 incremental sync，但 runner 使用标准允许的完整文档 replacement，
避免把测试语义绑定到编辑器的单次按键 range。`publishDiagnostics.version` 目前
可缺失。

## 文档

- [总体架构](docs/ARCHITECTURE.md)
- [项目申报书](docs/PROJECT_PROPOSAL.md)

## 许可证

Apache-2.0。实现和 fixture 均为本项目自行编写；仅参考 LSP 规范、rustc
compiletest 与 gopls marker 的交互思想，不复制其代码。
