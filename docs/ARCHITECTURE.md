# 总体架构

`moon-lsp-compiletest` 是一个面向 MoonBit 的 LSP 诊断回归测试工具，以
compiletest 风格源码内联断言驱动真实 `moon-lsp --stdio`，验证单个文件从
`before.mbt` 到 `after.mbt` 的 `publishDiagnostics`。项目由九个 MoonBit 包组成：
公开诊断模型、marker parser、Content-Length framing、窄 LSP 协议、async session、
最大一一 matcher、根 facade、CLI 与 mock/真实互操作测试。

## 1. 包与责任

| 位置 | 已交付责任 |
|---|---|
| `src/model` | 公开 diagnostic、expectation、case result 与 error 类型。 |
| `src/internal/marker` | 严格源码 marker parser。 |
| `src/internal/framing` | 增量 Content-Length codec。 |
| `src/internal/protocol` | 窄 JSON-RPC/LSP 编解码、capability 预检、file URI。 |
| `src/internal/session` | stdio process、路由、trace、timeout、关闭。 |
| `src/internal/matcher` | 确定性最大一一匹配与 diff。 |
| `src` | 临时 workspace、两阶段编排、facade/report。 |
| `src/cmd/moon-lsp-compiletest` | 参数、stdout/stderr 与退出码。 |
| `src/test/mock_lsp`、`tests` | deterministic mock、故障场景、真实互操作 fixture。 |

## 2. 分层与依赖

分层自上而下为：CLI → 根 facade/runner → marker + matcher → session → protocol +
framing + 原生 async process；`model` 为所有公开值类型提供归属，mock LSP 与真实
fixture 走同一 session 边界。

依赖方向只由 CLI/facade 指向 internal 与 model；session 指向 protocol/framing；
mock 指向 protocol/framing。不存在 internal 到 facade/CLI 的反向依赖。

## 3. 单 case 数据流

每个 case 依次经过：解析 before/after marker → 创建临时 `moon.mod`、`src/moon.pkg`
与 `src/case.mbt` → 运行隔离 `moon check` 生成 `_build/packages.json` →
initialize/initialized/didOpen(v1) → 写入并 didChange(v2 全文)/didSave/监听通知 →
过滤目标 publishDiagnostics → 固定 settle delay 后匹配 before → 写入并 didChange
(v3 全文)/didSave/监听 → 过滤并匹配 after → didClose/shutdown/exit → 产出 CaseResult。

## 4. 架构约束

- 全文 replacement 是 LSP 允许的 text-sync 形式；虽 server 声明 incremental sync，
  本工具不模拟按键级 range 编辑。
- 当前 diagnostics 可以无 version，settle delay 只避免阶段过快推进，不等同于
  通用多通知收敛。
- 所有 `internal/*` 都不由 CLI 直接导入，公开具体类型由 `model` 拥有并由根
  facade 重导出。
- 首版仅面向 Linux native；依赖 `moonbitlang/async`；外部驱动 `moon-lsp --stdio`。
- 当前 native `moon-lsp` 读取临时 module 的 `_build/packages.json`，runner 在启动
  LSP 前运行一次隔离 `moon check` 生成该索引；before 源码带诊断时该检查的非零
  退出属预期，其输出保存在临时工作区，LSP 仍是唯一被断言的诊断来源。

## 5. 目录结构

- `src/model` — 公开值类型
- `src/internal/{marker,framing,protocol,session,matcher}` — 内部实现
- `src/` — 根 facade/runner
- `src/cmd/moon-lsp-compiletest` — 可执行 CLI
- `src/test/mock_lsp` — 确定性 server
- `tests/{cases,failure-cases}` — 真实 fixture

## 6. 关键设计决策（ADR）

### 模型

| ADR | 选择 | 未选方案 | 理由 | 代价 |
|---|---|---|---|---|
| ADR-M01 | 公共 model package | internal 类型经 facade 强行重导出 | 保持构造/方法所有权和 mbti 清晰 | 多一个公开 package |
| ADR-M02 | code 为 string/number enum | 全部转 String | 保留 LSP 原始语义 | matcher 多一个分支 |
| ADR-M03 | severity 可选 | 缺失时默认 Error | 规范允许缺失，避免假信息 | 期望匹配需处理 None |

### marker

| ADR | 选择 | 未选方案 | 理由 | 代价 |
|---|---|---|---|---|
| ADR-MK1 | 仅 `//~^` | Rust 全部 marker 变体 | 首版语义更易解释和测试 | 多诊断复杂布局表达力有限 |
| ADR-MK2 | 字面消息子串 | regex | 稳定、安全、无需方言解释 | 不能表达可变数字 |
| ADR-MK3 | 严格行尾 | 容忍未知 token | 防止拼写错误静默通过 | fixture 迁移更严格 |

### framing

| ADR | 选择 | 未选方案 | 理由 | 代价 |
|---|---|---|---|---|
| ADR-F01 | 自有增量 state machine | `read_until` 后直接读 body | 更容易测试粘包和预读字节 | 需要维护 buffer |
| ADR-F02 | UTF-8 Bytes 长度 | String length | 符合 LSP 规范 | 必须显式 encode/decode |
| ADR-F03 | 默认严格单 Content-Length | 宽松忽略重复 header | 防请求走私和歧义 | 兼容极不规范 server 较差 |

### protocol

| ADR | 选择 | 未选方案 | 理由 | 代价 |
|---|---|---|---|---|
| ADR-P01 | 手写所需消息 shape | 生成完整 LSP types | 范围清楚、编译更轻 | server 扩展需显式实现 |
| ADR-P02 | 先看 method 再看 id | 仅按 id 路由 | 防 server/client ID 数值碰撞 | classifier 稍复杂 |
| ADR-P03 | POSIX file URI | 跨平台 URI abstraction | 首版 Linux native 可验收 | Windows 后续另做 |
| ADR-P04 | 默认 UTF-16 | 多 encoding 协商 | 规范默认且匹配当前 server | 通用性有限 |

### session

| ADR | 选择 | 未选方案 | 理由 | 代价 |
|---|---|---|---|---|
| ADR-S01 | 每 case 独立进程 | 共享 server | 最大化状态隔离 | 执行较慢 |
| ADR-S02 | stdout/stderr 并发 drain | 结束后 read stderr | 防 pipe deadlock | 需要结构化并发 |
| ADR-S03 | target URI + fixed settle delay | 第一条 diagnostics | 避免阶段过快推进 | 不提供多通知收敛证明 |
| ADR-S04 | 协议关闭优先 | 直接 kill | 留给 server 正常清理 | timeout 路径复杂 |

### matcher

| ADR | 选择 | 未选方案 | 理由 | 代价 |
|---|---|---|---|---|
| ADR-MA1 | 穷尽一一匹配 | `any()` contains | 捕获额外/重复诊断 | 算法稍复杂 |
| ADR-MA2 | 最大匹配 | greedy 首候选 | 避免重叠期望顺序依赖 | 需证明确定性 |
| ADR-MA3 | 字段级语义 diff | raw JSON diff | 用户能直接定位错误 | 要维护格式 |

### facade / runner

| ADR | 选择 | 未选方案 | 理由 | 代价 |
|---|---|---|---|---|
| ADR-R01 | 两文件 case | 单文件 revision DSL | 直观且不扩 parser | 文件数翻倍 |
| ADR-R02 | 独立临时 module | 在用户项目原地修改 | 无污染且 URI 唯一 | 需要 fixture copy |
| ADR-R03 | assertion 进 CaseResult | 全部抛 Error | CLI 能区分退出 1/2 | 两种错误通道 |
| ADR-R04 | 串行 suite | 默认并行 | 诊断和资源更确定 | 总耗时较长 |

### CLI

| ADR | 选择 | 未选方案 | 理由 | 代价 |
|---|---|---|---|---|
| ADR-C01 | 0/1/2 三类退出码 | 全失败都 1 | CI 可区分断言和基础设施 | 需固定优先级 |
| ADR-C02 | 默认文本报告 | 默认 JSON | 人工和 CI 日志易读 | 机器集成后续 |
| ADR-C03 | server command 可配置 | 写死本机绝对路径 | 工具链安装位置可变 | 需校验 PATH |

### mock / 互操作

| ADR | 选择 | 未选方案 | 理由 | 代价 |
|---|---|---|---|---|
| ADR-T01 | mock + real 两层 | 只真实 server | 可注入故障又保留互操作证据 | 维护两类测试 |
| ADR-T02 | 编译时 scenario | YAML mock script | 不引入另一套 DSL | 新场景需写代码 |
| ADR-T03 | error→fixed 主 demo | clean→error | 显式空数组提供强 clear 证据 | before 必须有诊断 |
