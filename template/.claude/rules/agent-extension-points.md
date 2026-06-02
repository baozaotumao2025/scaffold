---
paths:
  - "agent/**"
---

# Agent 扩展点规范

providers / export / storage / llm 四个扩展点的统一模式：端口（Protocol）+ 适配器多实现 + registry 工厂。

## 扩展点规范（providers / export / storage）

四个扩展点（含 llm）都遵循同一模式：**端口（Protocol，统一声明于 `domain/ports.py`）+ 适配器多实现 + registry 工厂**。调用方只依赖端口，按配置选实现，新增能力不改调用方。

下面端口为**示范**，按项目实际定义：

```python
# domain/ports.py —— 所有端口在此声明（六边形架构：端口属领域核心）
class Exporter(Protocol):
    async def export(self, data: object, out_path: Path) -> Path: ...

class StorageBackend(Protocol):
    async def save(self, key: str, data: bytes) -> None: ...
    async def read(self, key: str) -> bytes: ...
    def url_for(self, key: str) -> str: ...

class ExternalProvider(Protocol):
    def build_context(self) -> str: ...   # 注入 LLM prompt 的外部上下文
```

**节点必须通过接口调用，禁止硬编码具体实现：**

- `finalize` 节点调用 `exporter.export(...)`，不直接调具体导出库
- 所有文件读写经 `StorageBackend`，不直接碰 `Path.write_bytes`（本地实现内部才碰 FS）
- 加新导出格式 = 新增 `xxx_exporter.py` 注册到 registry，`finalize` 一行不改

## registry 工厂

每个扩展点目录提供 `registry.py`，按 `Settings` 配置选择具体实现：

- `llm/`：按厂商配置选 `GeminiCliSession` 等 `LLMSession` 实现
- `providers/`：按配置选具体 `ExternalProvider` 实现（含 `none` 退化态）
- `export/`：按导出格式选具体 `Exporter` 实现
- `storage/`：按存储后端选 `local_storage`（未来 `s3_storage`）等 `StorageBackend` 实现

新增能力 = 新增一个实现文件 + 在对应 `registry.py` 注册，调用方（DAG 节点）零改动。
