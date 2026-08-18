# moon-lsp-compiletest 项目申报书

## 基本信息

- 项目名称：moon-lsp-compiletest
- 参赛者：yinlaomo112
- 联系方式：tiank0823@163.com
- GitHub 仓库链接：https://github.com/yinlaomo112/moon-lsp-compiletest
- 项目方向：MoonBit 工程基础设施 / LSP 诊断回归测试
- 是否为移植项目：否（原创实现）

## 项目简介

`moon-lsp-compiletest` 是一个面向 MoonBit 的 LSP 诊断回归测试工具。它采用
compiletest 风格的源码内联断言，通过真实 `moon-lsp --stdio` 验证单个文件从
`before.mbt` 到 `after.mbt` 的 `publishDiagnostics`。

MoonBit 的 compiler 输出测试无法覆盖 LSP stdio framing、文档同步、异步通知、
file URI 与诊断清空等行为。本项目提供一个可复用的 Linux native CLI 与 facade：
用例只需 `before.mbt`、`after.mbt` 和 `//~^` marker；runner 在隔离工作区中启动
server，严格匹配目标 URI 的诊断并给出稳定 diff。

## 核心功能范围

- 严格 `//~^` 源码 marker，支持 severity、可选错误码与字面消息子串。
- UTF-8 Content-Length framing 与窄 JSON-RPC/LSP 协议编解码。
- 每 case 独立临时 module 与独立 `moon-lsp` 进程，不修改用户工作区。
- before/after 两阶段全文文档更新与显式空 diagnostics 清除验证。
- 确定性最大一一诊断匹配与字段级语义 diff。
- 0/1/2 三类退出码、trace 记录、stdout/stderr 与稳定报告。
- Mock 故障路径注入与真实 `moon-lsp v0.10.4` 互操作用例。

## 原创或参考说明

本项目为原创 MoonBit 实现，九个模块（公开诊断模型、marker parser、framing、
窄 LSP 协议、async session、matcher、facade、CLI、mock/互操作）均为自行编写。
设计上仅参考 LSP 3.17 规范、rustc compiletest 与 gopls marker 的交互思想，不复制
其代码或生成类型。根许可证为 Apache-2.0，唯一第三方依赖为 `moonbitlang/async`。

首版明确不做通用 LSP framework、completion/hover、YAML DSL、golden/bless、
多文件/多 revision 或跨平台承诺；仅面向 Linux native。
