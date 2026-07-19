# Starport Market / 星港集市

一个 18 天一局的 Pyxel 科幻夜市经营游戏。你要观察市场事件和顾客偏好，决定进货、售价、营销与永久升级，在库存过期和现金压力之间建立自己的经营路线。

它同时也是一个 Agent 环境：人类界面和 JSON Agent 使用同一个确定性规则核心，不需要让 Agent 截图、识字或模拟按键。

## 现在就玩

```powershell
cd D:\starport-market
python -m venv .venv
.\.venv\Scripts\python.exe -m pip install -e ".[dev]"
.\.venv\Scripts\python.exe play.py
```

已初始化好的当前工作区可以直接执行最后一行。

Windows 下也可以直接双击 `run_game.bat`；首次运行会自动创建项目内环境并安装依赖。`run_agent_demo.bat` 会让参考 Agent 连续经营 10 局。

### 操作

| 按键 | 功能 |
| --- | --- |
| `↑` / `↓` | 选择商品 |
| `←` / `→` | 减少 / 增加进货量 |
| `Z` / `X` | 降低 / 提高售价 |
| `C` | 切换营销方案 |
| `U` | 切换永久升级 |
| `Space` / `Enter` | 开市 / 进入下一天 |
| `H` | 打开两页游戏内教程 |

## 经营内容

- 5 种风险收益不同的商品，其中三种有保质期；库存按先进先出出售。
- 6 类顾客，各有偏好标签、价格敏感度和忠诚度。
- 18 种市场事件，同时影响需求、进货价、声望或临时容量。
- 5 种营销方案，包含成本、需求提升和声誉反噬风险。
- 9 项永久升级，覆盖仓储、洞察、品牌与自动化四条路线。
- 18 天确定性市场日程；相同 seed 和相同行动永远得到相同结果。
- 动态星空、像素商品、夜市场景、声音、日报和五档最终评级。

## Agent 快速入口

查看完整 action schema 和初始 observation：

```powershell
.\.venv\Scripts\python.exe -m starport_market.agent_cli schema --seed 7
```

让参考 Agent 完整经营 20 局：

```powershell
.\.venv\Scripts\python.exe -m starport_market.agent_cli autoplay --seed 7 --episodes 20
```

启动 JSON Lines 会话：

```powershell
.\.venv\Scripts\python.exe -m starport_market.agent_cli serve --seed 7
```

服务首先输出初始观察。之后每行输入一个行动对象：

```json
{
  "orders": {
    "glow_noodles": 4,
    "plasma_fruit": 2,
    "void_tea": 3,
    "meteor_jerky": 1,
    "holo_charm": 0
  },
  "prices": {
    "glow_noodles": 9,
    "plasma_fruit": 16,
    "void_tea": 7,
    "meteor_jerky": 10,
    "holo_charm": 24
  },
  "campaign": null,
  "upgrade": null
}
```

非法行动返回结构化错误，并带 `state_unchanged: true`。协议、观察字段和集成示例见 [docs/AGENT_API.md](docs/AGENT_API.md)。

## 验证

```powershell
.\.venv\Scripts\python.exe -m pytest
.\.venv\Scripts\python.exe -m starport_market.agent_cli autoplay --seed 100 --episodes 50
```

当前测试覆盖确定性、状态导出恢复、行动原子性、容量骤降、库存过期、同日扩容、JSON 序列化、JSONL 错误恢复和完整 Agent 对局。

## 结构

```text
starport_market/
  core.py          # 唯一规则核心，不依赖 Pyxel
  agent_env.py     # Gym 风格纯字典接口
  agent_cli.py     # JSONL / schema / autoplay
  bot.py           # 只读取公开 observation 的参考策略
  ui.py            # Pyxel 人类表现层
  data/content.json
tests/
```

内容资源初稿由 Kimi K3 经 ACP 生成，规则架构、筛选、实现、平衡与验收由 Codex 完成。
