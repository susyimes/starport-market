# Starport Market — Godot 4（v3《暗涌夜市》）

Dockline 风格星港夜市经营 sim（默认中文）。v3 全面重构：像素美术与 UI 重做（「Dockline Neon」设计系统），玩法从"照预测执行"重做为**风险管理**——一切收益先押代价，赢是判断的奖赏，输的人能说出自己哪一步贪了。

经济规则只在 `scripts/core/market_game.gd`，数值全部在 `data/content.json`（表驱动）；UI 不写规则。确定性 seed：同 seed 同结局。

## 玩法（18 夜 = 三幕 + 终夜）

每夜规划 → 开市结算。核心系统：

- **风声与行情**：今晚事件确定；明晚以双候选+概率预告；进价每日波动带 5 夜走势。押风声囤货：赌中吃需求窗口，赌错抱着过期货。
- **契约看板**：现货急单 / 跨夜大单（收定金、有交期）/ 夜 15 终极大单。接单担责：违约罚金+掉声望。
- **走私与热度**：私货便宜四成，每件+热度；热度决定开市查验概率（提前显示）。中查没收全部私货+罚款。
- **路线牌**：夜 1/7/13 三次不可逆二选一（正规牌照/灰道人脉 → 冷链协约/码头中介 → 贵宾名录/缉私内线）。
- **黄昏访客**：按处境上门的具名角色（收尾贩子·老盖 / 缉私线人·三只手 / 情报贩子·耳朵 / 豪客·九公主）。
- **人情点**（0-3）：免一次违约 / 免一夜租金 / 成本价急补货。
- **债务与破产**：可向钱庄·半两借款；负现金计息；连续 3 夜资不抵债 →「清算离港」。
- **赛季弧线**：租金 $12→$22→$34 递增；夜 6/12 港务考核（目标提前公示）；夜 16 起供应收口、夜 18 批发市场关闭——终夜大离港只能卖囤下的货。

终局分 = 现金 + 库存清算 − 债务 + 声望×5 + 履约×10 − 违约×20（+终极大单 150），全程可在风险台账查看。段位：太空垃圾 → 浮木 → 夜鹰 → 码头老板 → 轨道大亨 → 星港传奇。

## 操作

| 键 | 作用 |
| --- | --- |
| Space / Enter | 开摊 / 开市 / 继续 |
| ↑↓ / ←→ | 选货 / 进货 |
| Z / X | 标价 |
| 1 / 2 | 路线牌二选一（夜 1/7/13） |
| 3–5 | 契约接受/放弃 |
| R | 风险台账（热度·查验率·债务·考核·终局分） |
| V / F / L / B | 访客 / 人情点 / 借款 / 升级 |
| H / Esc | 帮助 / 退出 |

鼠标可直接点击所有行卡、契约卡、走私 stepper 与按钮。

## 环境与验证链

| 组件 | 说明 |
| --- | --- |
| Godot | 4.7.1（winget `GodotEngine.GodotEngine`），CLI shim `../tools/bin/godot.cmd` |
| 美术 | 全部由 `tools/gen_art.py` 程序化生成（Python + PIL + numpy），无外部素材 |
| 设计契约 | `../docs/redesign-v3-spec.md`（美术+UI）、`../docs/gameplay-v3-final.md`（玩法） |

```powershell
$godotConsole = "$env:LOCALAPPDATA\Microsoft\WinGet\Packages\GodotEngine.GodotEngine_Microsoft.Winget.Source_8wekyb3d8bbwe\Godot_v4.7.1-stable_win64_console.exe"

# 运行游戏
.\tools\bin\godot.cmd --path godot

# 重新生成全部像素美术（联览图输出到 godot/.preview/gen/）
python godot\tools\gen_art.py --preview
& $godotConsole --path godot --headless --import

# 逻辑冒烟（确定性双跑、逐夜现金流恒等式、契约/查验/访客/破产分支，输出 SMOKE_OK）
& $godotConsole --path godot --headless -s res://tools/smoke_test.gd

# 平衡回归（3 策略机器人 × 200 seed = 600 局，输出 BALANCE_JSON）
& $godotConsole --path godot --headless -s res://tools/balance_test.gd

# 四界面截图巡检（短暂弹窗，输出到 godot/.preview/）
& $godotConsole --path godot -s res://tools/screenshot.gd
```

平衡基准（改数值后跑 balance_test 对照）：保守流 均分 ~1138 / 破产 0.5%；均衡流 ~1902 / 3%；贪婪流全局 ~1270 / 破产 31.5%、存活局均分 ~2013 为三者最高；保守均分必须低于均衡（退化检测）。

## 结构

```
godot/
  project.godot
  data/content.json      # 全部数值：货品/客群/事件(phase_weights+风声)/升级4项/契约/走私热度/路线牌/访客/考核/终夜/钱庄/计分
  data/loc_zh.json       # 中文文案（含具名角色台词）
  scripts/core/          # MarketGame v3 经济（四接口：try_quote_action/try_step/observation/terminal_summary）
  scripts/ui/            # Dockline Neon UI + 夜市场景
  scenes/main.tscn
  assets/                # backgrounds/ characters/ icons/ ui/（全部 gen_art.py 生成）
  tools/gen_art.py       # 像素美术管线（唯一资产来源）
  tools/smoke_test.gd    # 逻辑冒烟
  tools/balance_test.gd  # 平衡机器人
  tools/screenshot.gd    # 截图巡检
.backup-v2/              # v2 全量备份（代码+资产），可整体回滚
```

v2 → v3 已删除：广告系统、每夜随机执照、自动结算悬赏、纯数值升级 3 项、里程碑经济奖励（降级为徽章）。Python 原型 `starport_market/core.py` 已分叉，Godot 版为正典。
