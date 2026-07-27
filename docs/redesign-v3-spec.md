# Starport Market v3 重设计规范 — "Dockline Neon"

统一契约：美术管线（`godot/tools/gen_art.py`）与 UI（`godot/scripts/ui/game_ui.gd`、`market_scene.gd`）都必须遵守本规范。目标：保留「星港夜市霓虹」识别度，工艺全面升级——告别 v2 的简陋方块感。

## 0. 硬性约束（两条线都必须遵守）

- 经济规则只在 `scripts/core/market_game.gd`，UI/美术**绝不**改 core。
- `game_ui.gd` 对外 API 必须保留（`tools/screenshot.gd` 与 `tools/smoke_test.gd` 会调用）：
  `game` 字段、`enter_plan()`、`select_product(i)`、`adjust_order(d)`、`adjust_price(d)`、`select_permit(i)`、`cycle_campaign()`、`cycle_upgrade()`、`open_market()`、`continue_from_report()`、`new_game(seed)`、`show_mode(m)`、`Mode` 枚举。
- `market_scene.gd` API 保留：`set_mode(m)`、`set_focus_group(gid)`、`tick(delta)`。
- 资产文件名不变（代码引用按路径）：
  - `assets/icons/product_<id>.png`，id ∈ neon_skewer, star_donut, ion_soda, void_jelly, meteor_popcorn, holo_sticker, orbit_plush, quantum_coffee
  - `assets/characters/customer_{dock,pilot,tourist,monk,scrap,luxe}.png`、`vendor_m0x.png`、`stall.png`
  - `assets/backgrounds/bg_dock.png`
  - `assets/ui/dot_glow.png`（gen_art.py 目前**没有**生成它——v3 必须补上）
  - v3 新增 UI 贴图（gen_art.py 生成）：`assets/ui/vignette.png`（边缘暗角）、`assets/ui/scanlines.png`（可平铺细扫描线）
- 新增中文文案一律走 `data/loc_zh.json` 的 `ui` 段（可增键，不改已有键义）；代码里用 `Loc.t("key")`。
- 中文字体：SystemFont（Microsoft YaHei UI 优先）。标题/数字可用 `font_weight = 700` 做粗体变体。

## 1. 调色板（美术与 UI 共用，UI 十六进制）

| 名称 | HEX | RGB | 用途 |
|---|---|---|---|
| bg-deep | #0A0C16 | 10,12,22 | 最底背景 |
| panel | #101322 | 16,19,34 | 主面板（alpha 0.96）|
| panel-alt | #161A2E | 22,26,46 | 次面板 |
| panel-inset | #0C0F1D | 12,15,29 | 内嵌/行卡 |
| border | #2A3050 | 42,48,80 | 常规描边 |
| border-hi | #3D4670 | 61,70,112 | 亮描边/悬停 |
| text | #E8ECF8 | 232,236,248 | 主文字 |
| dim | #8B93B0 | 139,147,176 | 次文字 |
| faint | #5A6180 | 90,97,128 | 弱文字 |
| lime | #B8FF3D | 184,255,61 | 主强调（CTA/选中）|
| violet | #9A7BFF | 154,123,255 | 事件/声望 |
| gold | #FFD166 | 255,209,102 | 金钱/悬赏 |
| mint | #3DFFA8 | 61,255,168 | 利润/成功 |
| red | #FF4D6D | 255,77,109 | 亏损/缺货 |
| cyan | #4DE3FF | 77,227,255 | 信息/科技 |
| magenta | #FF6EE7 | 255,110,231 | 装饰霓虹 |

像素画轮廓统一 #0D0F1A。

## 2. 像素画工艺规则（gen_art.py）

1. 每个精灵：1px 深色轮廓（#0D0F1A）+ **三阶明暗**（亮/本/暗），光源左上方，霓虹环境允许彩色边缘光（rim light：受灯一侧 1px 提亮）。
2. 允许少量抖动（dither）过渡，禁止大面积纯色方块直接当造型。
3. 剪影优先：先保证黑影轮廓可辨识，再上色。
4. 输出一律 `Image.NEAREST` 整数倍放大，禁模糊（背景的辉光/雾除外）。
5. 基准尺寸（可微调但保持量级）：
   - 图标 24×24 ×10 → 240px；角色 32×44 ×10；摊位 128×80 ×6；背景 480×270 ×4 = 1920×1080。
   - dot_glow 64×64 径向渐变；vignette 320×180（高斯羽化暗角）；scanlines 4×4 可平铺（1px 暗行，alpha≈28）。

### 2.1 背景 bg_dock（重点，当前最简陋）
多层构图，由远及近：
1. 天空：navy→violet 抖动渐变（用 2×2 dither 过渡代替硬色带）；星星（3 档亮度 + 少量十字闪）；淡紫/青**星云**雾团（低alpha椭圆+高斯）。
2. 右上**带环行星**：本体三阶明暗 + 环带（前后遮挡关系正确，环在行星后半部分被遮住）。
3. 远景航道：1–2 艘小飞船剪影 + 引擎光点、红/青航行灯。
4. 中景空港天际线**两层**：远层纯剪影偏暗；近层建筑带窗灯（暖黄/青，稀疏不均匀）、2–3 块霓虹广告牌（描边荧光+微光晕）、塔吊/龙门架剪影、垂落线缆。
5. 近景地面：码头金属板（横向接缝线 + 铆钉点），霓虹**竖向倒影**（多色、断续抖动），2–3 处水洼高光。
6. 底部薄雾 1–2 条（低 alpha 高斯）。
构图注意：中央上部留呼吸空间（title/plan 界面文字压在上面），视觉重心在下半。

### 2.2 摊位 stall
128×80：斜纹遮阳篷（双色 + 扇贝边 + 底缘暗面）、篷下暖光渐变、霓虹招牌（发光描边 + 类文字划线）、货架上 8 款商品的迷你可辨识版本（对应 8 图标配色）、玻璃展示柜（斜高光）、柜台木/金属质感、两侧立柱 + 挂灯笼（发光）+ 电缆、蒸汽丝、地面接触阴影。

### 2.3 角色（6 客群 + 摊主）32×44
剪影各异、职业特征明确、三阶明暗：
- dock 码头工：安全帽+头灯、荧光背心、工装、手套，壮实。
- pilot 飞行员：白色飞行服、镜面头盔（面罩青色反光斜条）、胸前仪表。
- tourist 游客（外星）：花衬衫、宽檐草帽、相机挂脖、薄荷肤色、触角。
- monk 夜巡僧：深紫兜帽长袍（帽内全黑+青色发光双眼）、念珠、提灯（发光）。
- scrap 废料商：护目镜、工具背包（外挂扳手/管件）、围巾、补丁夹克。
- luxe 豪客：白金披风、单片镜、金链、背头，气场足。
- vendor_m0x 摊主机器人：CRT 头（青绿扫描线+lime 笑脸）、天线、围裙、机械臂、轮式底盘。

### 2.4 图标 24×24（8 款商品）
造型饱满居中占画布 ~80%，三阶明暗 + 高光点 + 1–2 颗星光缀点；底部 1px 半透明接触影。neon_skewer 烤串 / star_donut 甜甜圈 / ion_soda 汽水 / void_jelly 果冻 / meteor_popcorn 爆米花 / holo_sticker 贴纸 / orbit_plush 玩偶 / quantum_coffee 咖啡。

## 3. UI 设计系统（game_ui.gd）

### 3.1 基础
- 8px 间距栅格；面板圆角 12、卡片 10、chip 6。
- 面板：`StyleBoxFlat` bg=panel(0.96)+1px border(#2A3050)+shadow(黑35%, size 8, offset 0,3)。
- 主按钮（CTA）：lime 填充、深色文字、**霓虹光晕**（shadow_color=lime alpha 0.35, shadow_size 12）、hover 提亮、pressed 压暗；次按钮描边式，hover 时边框换强调色。
- 节标题（section header）：左侧 3×14 lime 竖条 + 12px dim 加粗字，可带右侧快捷键 chip。
- chip：inset 底 + 6 圆角 + 11px 文字，用于快捷键提示、标签、状态。
- 数字一律粗体（font_weight 700 的 SystemFont 变体）。
- 全屏叠加：`vignette.png`（FULL_RECT，alpha≈0.5）+ `scanlines.png` 平铺（alpha≈0.05），置于最顶层且 `mouse_filter = IGNORE`。

### 3.2 标题屏
左（38%）品牌面板：DOCKLINE·7号泊位 chip → 「星港市集」64px 粗体双层光晕（lime 外晕+白字）→ 金色 tagline → dim 简介 → 特性 chips 行（18夜/8货品/悬赏/执照）→ 摊主立绘 → 大 CTA「开启摊位」（呼吸脉冲光晕动画：shadow_size 随 sin 波动）→ 操作提示 + 种子。右（62%）实况码头面板：顶部小节标题，市景四周 1px lime 亮边框。

### 3.3 备货屏（信息密度最高，重点重排）
- 顶部 4 个指标卡：3px 强调色左条 + 图标位 + 11px dim 标签 + 22px 粗体数值（夜次 lime / 信用点 gold / 声望 violet / 货舱 mint，货舱接近满载变 red）。
- 事件条：violet 左条 + 事件名 20px + 副标 dim；右侧客群卡（客群像 48px 内嵌板 + 名 + 偏好 tags chips）。
- 左列（64%）货舱清单：**列头行**（货品/库存/进货/标价/成本/预估，dim 11px，右对齐数字列）+ 8 张行卡（72px）：图标托板（40px inset 圆角）→ 名称 15px 粗体 + tags 11px faint → 数字列固定宽右对齐（等宽感）。悬赏商品行：gold 左条 + 「悬赏」chip。选中行：lime 1.5px 边 + bg 提亮 + ▶；hover 亮边。**行内 stepper**：选中行显示 − / + 小按钮（进货）与 ↓/↑（标价）可点。
- 右列（36%）策略面板从上到下：计划（键值对齐两列：支出/余款/货舱/预估，数值右对齐粗体，余款不足变 red）→ 执照二选一（两张竖卡：[1] chip + 名粗体 + desc dim，选中=lime 填充深字，未选=描边）→ 悬赏卡（gold 边 + 图标托板 + 「今晚悬赏」chip + 单价×数量 + 声望奖励）→ 广告/升级两张 mini 卡（当前选择 + 价格 + 点击循环）。
- 底部详情条：图标托板 56px + 名称 17px 粗体 + 描述 dim；右侧 tip/警告区（警告 red 图标 + 文案）；最右大 CTA「开市营业」。

### 3.4 结算屏
顶部：「夜次 02 · 收摊」24px + 利润主数字 34px（正 mint / 负 red）+ flavor dim。市景条（living 模式）。4 指标卡（营业额/售出/损耗/利润）。悬赏结果横幅（gold 边横条，达成✓/未达成）+ 里程碑横幅（violet）。商品表：**列头**（货品/售出/缺货/营收）+ 斑马纹行 + 数字右对齐，缺货 red chip。成本行 chips（进货/租金/声望Δ/现金）。右下 CTA「继续」。

### 3.5 终局屏
居中大卡：「本季结束」gold → 左侧奖章面板（段位 34px gold + 分数 + 摊主立绘 + 光晕）→ 右侧「最终账本」表格（键左值右对齐，8 行）→ flavor → 两按钮（新种子 gold 填充 / 回标题描边）。

### 3.6 帮助浮层
暗幕 0.8 + 中央 860×560 卡：标题 + 正文 15px 行距 1.4 + 页脚「←→ 翻页 · H 关闭」chips + 页码点。

### 3.7 市景 market_scene.gd
保留 API；随资产更新调整锚点比例（stall/角色尺寸变了）；新增：摊位背后暖光晕（dot_glow 大尺寸 gold 低 alpha）、地面反光条、漂浮光尘保留但更细腻（3 档大小/速度）；living 模式顾客行走 + 靠近摊位时短暂停留（可选）；focus 客群 lime 光环 + 其余降透明。

## 4. 验证流程（必须跑通）

```bash
GODOT="/c/Users/svmes/AppData/Local/Microsoft/WinGet/Packages/GodotEngine.GodotEngine_Microsoft.Winget.Source_8wekyb3d8bbwe/Godot_v4.7.1-stable_win64_console.exe"
cd /d/starport-market
python godot/tools/gen_art.py --preview          # 重生成美术 + .preview/gen/ 预览图
"$GODOT" --path godot --headless --import         # 重导入资产（新增文件必须）
"$GODOT" --path godot --headless -s res://tools/smoke_test.gd   # 逻辑冒烟（必须 PASS）
"$GODOT" --path godot -s res://tools/screenshot.gd               # 四屏截图 → .preview/shot_*.png（会短暂弹窗）
```

美术线自查：Read `.preview/gen/*.png`；UI 线自查：Read `.preview/shot_*.png`。改完必须亲眼看图再收工。
