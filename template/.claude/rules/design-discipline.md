# 架构与设计纪律

> 六边形 + SOLID + 契约式设计（DbC）+ 高内聚低耦合 + 扩展点机制概述。

整体遵循**六边形架构（Ports & Adapters）+ 整洁架构**；类/函数级遵循 **SOLID** 与**契约式设计（Design by Contract）**。

## 六边形架构（Ports & Adapters）

- **端口（Port）**：领域定义的接口（`LLMSession` / `ImageProvider` / `Exporter` / `StorageBackend`），表达"领域需要什么能力"
- **适配器（Adapter）**：端口的具体实现（当前 LLM CLI 适配器 / `pptx_exporter` …），位于最外层，可替换
- 依赖方向恒指向领域；替换外层实现不触动内层

## SOLID（类/模块级强制）

| 原则 | 约束 |
|------|------|
| S 单一职责 | 一个类/函数仅一个变更理由 |
| O 开闭 | 扩展靠加实现，不改既有代码（即扩展点机制） |
| L 里氏替换 | 任一端口实现可无差别替换，不破坏调用方契约 |
| I 接口隔离 | 端口按消费者拆分，不强加无关方法 |
| D 依赖倒置 | 依赖抽象（Port），不依赖具体（Adapter） |

## 契约式设计（Design by Contract）——编码前先定契约

**任何函数/类：先定义契约（签名 + 前置条件 + 后置条件 + 不变量），再写测试，再写实现。**

- 前置条件（Precondition）：调用方须保证的输入约束
- 后置条件（Postcondition）：函数承诺的输出与副作用
- 不变量（Invariant）：对象生命周期内恒真的状态约束
- 契约落于类型签名 + docstring；关键不变量以断言运行时校验
- 公开接口的契约即其规格，**契约稳定性优先于实现自由**

## 核心设计原则（高内聚 / 低耦合）

上述纪律落到日常的可操作规则。**所有新功能从设计之初就遵循，不允许"先实现再重构"。**

1. **单一职责 + 高内聚**
   每个模块/类/函数只做一件事。相关逻辑聚在一起（如 PTY 机制全在 `llm/pty_bridge.py`），不相关的拆开。判据是**职责**而非行数：一个函数做了两类事就该拆；文件超 ~300 行是「该审视是否多职责」的信号，不是硬上限——单一职责的长文件不必为凑行数而拆。

2. **依赖方向（低耦合的硬规则）**
   依赖只能单向流动，禁止反向或跨层依赖（详见 `architecture.md`）。上层依赖下层，下层绝不反向 import 上层；`utils/` 是谁都可依赖的叶子层，自身不依赖任何业务模块。

3. **依赖抽象，不依赖实现（DI）**
   业务代码依赖**接口（Protocol/ABC）**，不依赖具体类。具体实现在边界处注入。
   范例：DAG 节点依赖 `LLMSession` 端口，不知道背后是哪个 CLI 厂商（端口见 `agent/domain/ports.py`）。
   实现类**必须显式继承 Protocol**（`class MyImpl(MyProtocol):`）并用 `@override` 标注每个实现方法——见下「Protocol 实现强制写法」。

4. **稳定契约解耦服务**
   三层之间只通过**消息契约**通信（WebSocket JSON 协议），不共享内部类型。契约是单一来源（见 `communication-protocol.md`），任一服务内部重构不影响其他服务。

5. **新功能 = 插到扩展点，不改核心**
   加新能力时，优先实现已有扩展点接口；若没有合适接口，**先定义新接口**再实现，禁止往核心流程里塞 if/else 分支。

## 扩展点机制概述（插件接缝）

系统预留以下接口，保证可扩展性。新增同类能力 = 新增一个实现，**不改调用方**。端口统一声明于 `agent/domain/ports.py`（六边形架构：端口属领域核心）；适配器实现散于对应目录。

| 扩展点（端口） | 当前适配器 | 适配器位置 | 未来扩展 |
|--------|---------|---------|---------|
| `LLMSession` | 当前 CLI 厂商适配器 | `agent/llm/` | 其他 CLI / API SDK |
| `ImageProvider` | unsplash / pexels / none | `agent/providers/` | 自建图库 / AI 生图 |
| `Exporter` | `pptx_exporter` | `agent/export/` | pdf_exporter / 长图 |
| `StorageBackend` | `local_storage`（本地 FS） | `agent/storage/` | S3 / OSS |

每个端口都是 `Protocol`，新适配器注册到工厂（`registry`）即生效，调用方按配置选择。具体端口签名与注册规范见 `agent.md`。

### Protocol 实现的强制写法（Python 3.12+）

实现端口时，**必须同时满足两条约束**，缺一不可：

1. **显式继承 Protocol**：`class MyImpl(MyProtocol):` — 让 mypy 能校验实现完整性，而非依赖鸭子类型隐式对齐
2. **`@override` 标注每个实现方法**：来自 `from typing import override`（Python 3.12）— 方法名拼错或接口改签名时，类型检查器立即报错，不等到运行时

```python
from typing import Protocol, override

# ✅ 强制写法
class GeminiCliSession(LLMSession):      # 显式继承，非隐式鸭子类型
    @override
    async def complete(self, prompt: str) -> str:
        result = await self._read_until_done()
        return result or ""

# ❌ 禁止：隐式对齐，接口改名或拼写错误时静默脱钩
class BadSession:
    async def complet(self, prompt: str) -> str:  # 拼错了，运行时才 crash
        ...
```

违规信号（Claude Code 应直接指出）：
- 实现类未继承 Protocol → mypy 无法验证实现完整性
- 实现方法缺少 `@override` → 接口改名后实现类静默脱钩，直到运行时才发现

## 可靠性纪律（Resilience，强制）

核心链路全是易抖动的外部依赖（LLM CLI 进程 / Chromium 截图 / 图床 HTTP），故跨边界调用必须假定**会超时、会瞬时失败、会被重复触发**。以下与「命令幂等」（见 `communication-protocol.md`）同属可靠性约束，从设计之初遵循，不允许"先实现再加兜底"。

1. **超时无处不在（Ubiquitous Timeout）**
   任何跨进程/网络/IO 的等待**必须设显式超时**，禁止裸 `await` 无界等待。
   - 外部调用统一用 `asyncio.timeout(...)` 或客户端原生 timeout 包裹；超时即抛领域错误（如 `GEMINI_TIMEOUT`），不静默挂起。
   - 超时值经 `.env` 注入、不硬编码（见 `config.md`）；每类外部依赖一个超时配置项。
   - 反例：`await proc.read()` 无超时 → 进程卡死则会话永久僵死。

2. **重试 + 指数退避 + 抖动（Retry / Backoff + Jitter）**
   对**幂等**操作的瞬时失败（网络抖动、图床 5xx、截图偶发失败）才允许重试；非幂等操作禁止盲目重试。
   - 重试须有**上限**（次数 + 总时长双封顶），退避用指数 + 随机抖动，禁固定间隔猛刷。
   - 重试逻辑收拢为一处可复用策略（如 `utils/retry.py`），不在各调用点散写循环。
   - 用户输入触发的命令依赖幂等键去重（见 `communication-protocol.md`），保证重试安全。

3. **降级而非整体失败（Graceful Degradation）**
   单个可选能力失败时，**降级到退化态**而非让整条生成链崩溃。
   - 经端口的退化实现承接：`ImageProvider` 失败/超额 → 降级到 `none`（无图）继续生成，而非中断 Deck。
   - 降级须**可观测**：记日志 + 必要时以事件告知前端（区别于 `error` 致命错误）。
   - 哪些能力可降级、降级到何种退化态，在端口契约里显式声明。

4. **边界校验，内部信任（Validate at Boundary）**
   不可信输入（前端命令、上传 `.md`、外部响应）在**适配器/路由边界一次性校验**（Pydantic / 类型 / 业务规则），校验失败回 `INVALID_INPUT`；越过边界进入领域后**信任已校验**，领域内不重复防御性判空。
   - 校验是边界职责，不是领域职责——领域用前置条件断言不变量，而非兜外部脏数据。

5. **资源管理强制（RAII / Context Manager）**
   持有外部资源（子进程 / pty fd / 浏览器页 / DB 连接 / 文件句柄）**必须用 context manager**（`with` / `async with`）或在 `finally` 确定性释放，禁手动 `open`/`close` 配对裸写。
   - 目的：连接被取消（WS 断开 → Task cancel）时资源仍确定性回收，杜绝僵尸进程与 fd 泄漏（落地细节见各 `*-concurrency.md`）。
