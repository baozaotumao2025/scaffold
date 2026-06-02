帮用户用这个 scaffold 生成一个新项目。

用户输入：$ARGUMENTS

## 步骤

1. 如果用户没有提供项目名，先问清楚以下信息（一次性问完，不要逐个问）：
   - 项目目录名（my-project）
   - 是否包含 backend（FastAPI）
   - 是否包含 frontend（React + Vite）
   - 是否包含 agent（LLM 服务）
   - 数据库：sqlite 还是 postgresql
   - 如果 include_agent=true，LLM provider：gemini-cli / openai-api / anthropic-api

2. 在用户指定的目录（或当前目录）运行 copier 命令：

```bash
copier copy git+https://github.com/baozaotumao2025/scaffold.git <项目目录> \
  --data project_name="<显示名称>" \
  --data include_backend=<true/false> \
  --data include_agent=<true/false> \
  --data include_frontend=<true/false> \
  --data database=<sqlite/postgresql> \
  --data llm_provider=<provider>   # 仅 include_agent=true 时加此项
```

3. 生成完成后，运行验证：
```bash
./scripts/verify.sh -v <项目目录>
```

4. 汇报生成结果和验证输出。如有失败项，给出修复建议。

## 注意

- 如果用户已在命令后直接提供了参数（如 `/new-project my-app backend+frontend`），直接解析并执行，不要再问一遍。
- 生成目录默认放在当前工作目录下。
- 不要修改 scaffold 模板本身。
