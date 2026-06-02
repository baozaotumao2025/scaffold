---
paths:
  - "agent/**"
---

# Agent 扩展点规范

providers / export / storage / llm 四个扩展点的统一模式：端口（Protocol）+ 适配器多实现 + registry 工厂。

## 扩展点规范（providers / export / storage）

四个扩展点（含 llm）都遵循同一模式：**端口（Protocol，统一声明于 `domain/ports.py`）+ 适配器多实现 + registry 工厂**。调用方只依赖端口，按配置选实现，新增能力不改调用方。

```python
# domain/ports.py —— 所有端口在此声明（六边形架构：端口属领域核心）
class Exporter(Protocol):
    async def export(self, screenshots: list[Path], out_path: Path) -> Path: ...

class StorageBackend(Protocol):
    async def save(self, key: str, data: bytes) -> None: ...
    async def read(self, key: str) -> bytes: ...
    def url_for(self, key: str) -> str: ...

class ImageProvider(Protocol):
    def build_prompt_context(self) -> str: ...   # 注入 gemini prompt 的图片来源说明
```

**节点必须通过接口调用，禁止硬编码具体实现：**

- `synthesize` 节点调用 `exporter.export(...)`，不直接调 python-pptx
- 所有文件读写经 `StorageBackend`，不直接碰 `Path.write_bytes`（本地实现内部才碰 FS）
- 加 PDF 导出 = 新增 `pdf_exporter.py` 注册到 registry，`synthesize` 一行不改

## registry 工厂

每个扩展点目录提供 `registry.py`，按 `Settings` 配置选择具体实现：

- `llm/`：按 `gemini_cmd` / 厂商配置选 `GeminiCliSession` 等 `LLMSession` 实现
- `providers/`：按 `image_source` 选 `unsplash` / `pexels` / `none` 等 `ImageProvider` 实现
- `export/`：按导出格式选 `pptx_exporter`（未来 `pdf_exporter`）等 `Exporter` 实现
- `storage/`：按存储后端选 `local_storage`（未来 `s3_storage`）等 `StorageBackend` 实现

新增能力 = 新增一个实现文件 + 在对应 `registry.py` 注册，调用方（DAG 节点）零改动。
