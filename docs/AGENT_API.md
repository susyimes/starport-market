# Agent API

Starport Market 的 Agent 接口只使用 Python 标准类型，核心不依赖 NumPy、Gymnasium 或 Pyxel。

## Python 环境

```python
from starport_market.agent_env import StarportEnv

env = StarportEnv(seed=42)
observation, info = env.reset()

while not observation["done"]:
    action = choose_action(observation, info["action_schema"])
    observation, reward, terminated, truncated, info = env.step(action)
```

返回值与 Gymnasium 的五元组兼容：

```text
observation, reward, terminated, truncated, info
```

`truncated` 当前始终为 `false`；一局在第 18 天结算，或现金为负且库存归零时破产。

## 每日行动

```json
{
  "orders": {"product_id": 0},
  "prices": {"product_id": 1},
  "campaign": null,
  "upgrade": null
}
```

- `orders` 与 `prices` 可以只写部分商品；缺失订单默认为 0，缺失售价沿用前一天。
- 一天最多选择一个营销和一个升级。
- 进货、营销、升级在同一事务中验证；超现金或超容量时整个行动拒绝。
- 合法价格上下界、当前升级价格和全部枚举值均随 observation 返回。

## 观察重点

- `market.event.effects`：当天公开的需求、成本、容量和声望变化。
- `market.customer_group`：偏好标签与价格敏感度。
- `products.*.forecast`：以当前售价计算的 `low/mid/high` 需求区间。
- `products.*.inventory.batches`：批次数量、年龄和剩余寿命。
- `products.*.unit_cost_today`：事件和自动化折扣后的真实单价。
- `market.upcoming`：由洞察升级解锁的未来事件或顾客信息。
- `last_report`：上一天逐商品需求、销量、缺货和财务分解。
- `state_digest`：规范化状态的 SHA-256，可用于复现与审计。

需求遵循公开关系：顾客偏好、事件标签、声望、升级、营销与价格弹性共同决定销量；只有 seed 派生的日级扰动不可直接观察。相同 seed、状态和行动的结果完全一致。

## JSON Lines 协议

```powershell
python -m starport_market.agent_cli serve --seed 42
```

特殊命令：

```json
{"command":"observe"}
{"command":"quote","action":{"orders":{},"prices":{}}}
{"command":"reset","seed":99}
{"command":"quit"}
```

`quote` 会完整验证计划并返回拟定价格下的需求区间和收入区间，但不推进游戏，也不改变状态。普通行动可以直接作为一行输入，也可以包装在 `{"action": ...}` 中。每个输出包都有 `type`：`reset`、`observation`、`quote`、`transition`、`error` 或 `bye`。

## 公平性

`HeuristicAgent` 只读取 observation，不访问事件日程、随机派生值或内部库存对象。它是可运行的协议示例和基准线，不是隐藏信息 Bot。
