# 阶段一 · 垂直切片详细设计

> 目标：**用最小的内容量，跑通一条完整的游戏闭环**，验证"这套玩法是否成立"。
> 这是全项目最重要的一个阶段——如果切片不好玩，后面所有内容都是白做。

---

## 1. 阶段范围

### 1.1 做（In Scope）

| 模块 | 本期做到 |
|---|---|
| 主菜单 | 新游戏 / 读档 / 退出 |
| 母港（简化） | 静态俯视场景，3 个可点击入口：**修理**、**市场**、**出航**；手动存档按钮 |
| 海域（仅图 1） | 8000×8000 固定海图，WASD + 点击航行，航门（占位，通往图 0） |
| 玩家船 | 1 级渔船（1 门炮），耐久/货舱/速度生效 |
| 敌舰 | 普通海盗 ×6、普通海怪 ×3（复用 2 个 EnemyDef） |
| 海怪 | 简化版独立模型：**躯体 + 2 条肢体 + 狂怒**（不做 4 肢体、不做喷吐），不能接舷、链弹无效 |
| 战斗 | 点击锁敌 + 自动齐射 + **四池部件损伤**（船体/帆/舵/船员）+ 弹药切换（实心/链弹/葡萄）+ 击沉与俘获结算 + 撤离（需帆舵完好） |
| 战利品 | 金币 + 1 种货物 + 15% 装备掉落（装备仅做数值入包，不可装备） |
| 经济（最简） | 市场买卖 4 种商品，价格随库存浮动 |
| 存档 | 1 个自动档 + 1 个手动档，JSON 原子写入 |
| UI | 航行 HUD、市场面板、战斗浮层、提示条 |

### 1.2 不做（Out of Scope，后续阶段）

- 图 2～9、Boss、任务、悬赏、声望、船员、基地建造、装备穿戴、多存档位、船只购买
- 燃烧弹（本期只做 3 种弹药）、接舷战浮层的完整表现、损伤美术（先用数值占位）
- 海怪材料的制造链（本期材料只入包、不可用）、魔法内容（全程不做，阶段四起）
- 游戏内时间轴与周结算（阶段二引入，本期市场库存按"每次进港刷新"临时简化）
- 音效音乐（先留接口）
- 美术精修（先用程序化几何）

---

## 2. 场景树设计

### 2.1 Main.tscn（根场景，常驻）

```
Main (Node)
├── SceneRouter (Node)              # 场景切换，带淡入淡出
├── TransitionLayer (CanvasLayer)
│   └── Fade (ColorRect)
└── ScreenStack (Node)
```

### 2.2 BaseScene.tscn（母港）

```
BaseScene (Node2D)
├── Island (Node2D)                  # 静态几何绘制的岛与建筑
│   ├── DrydockArea (Area2D)         # 可点击 → 修理面板
│   ├── MarketArea (Area2D)          # 可点击 → 市场面板
│   └── ExitArea (Area2D)            # 可点击 → 出航
├── Camera2D
├── BaseHUD (CanvasLayer)
│   └── TopBar (PanelContainer)      # 金币 / 耐久 / 船名 / 存档按钮
└── Panels (CanvasLayer)
    ├── RepairPanel
    └── MarketPanel
```

### 2.3 SeaScene.tscn（海域，图 1）

```
SeaScene (Node2D)
├── Terrain (Node2D)
│   ├── WaterLayer (ColorRect / shader)
│   ├── IslandDecor (Node2D)
│   └── ShallowBodies (StaticBody2D × N)   # 礁石碰撞
├── Spawner (Node)                          # SpawnDirector：按配额生成敌舰
├── Entities (Node2D)
│   ├── PlayerShip (CharacterBody2D)
│   └── (EnemyShip / SeaMonster 实例)
├── Gate (Area2D)                           # 返回母港
├── Camera2D                                # 跟随玩家，缩放 0.5
└── SeaHUD (CanvasLayer)
    ├── StatusBar（速度/耐久/货舱/金币）
    ├── MiniMap
    ├── TargetPanel（锁定目标血条 + 装填环）
    ├── AmmoBar（实心/链弹/葡萄 三选一）
    ├── ActionBar（接舷[条件亮起] / 撤离[条件亮起]）
    ├── Ticker（提示条）
    └── CombatOverlay（战斗浮层）
```

---

## 3. 脚本设计

### 3.1 核心层（core/）

| 脚本 | 职责 | 关键接口 |
|---|---|---|
| `game_state.gd` | 单一存档态（RefCounted） | `to_dict()` / `from_dict()` |
| `event_bus.gd` | 全局信号 | `hp_changed`, `cargo_changed`, `gold_changed`, `combat_finished`, `target_changed` |
| `data_registry.gd` | 加载 `data/` 下全部 .tres | `get_ship(id)`, `get_commodity(id)`, `get_enemy(id)` |
| `save_manager.gd` | JSON 读写、原子写、版本号 | `save(slot)`, `load(slot)`, `has_save(slot)` |
| `rng_service.gd` | 确定性随机 | `set_seed()`, `randf()`, `randi_range()` |
| `scene_router.gd` | 场景切换 + 淡入淡出 | `goto(scene_path, payload)` |

### 3.2 玩法层（systems/）

| 脚本 | 职责 |
|---|---|
| `ship_controller.gd` | 玩家船运动：三种输入模式、转向惯性、速度、搁浅 |
| `ship_stats.gd` | 由 ShipDef + 装备 + 船员计算出的最终属性（本阶段只有 ShipDef） |
| `combat_resolver.gd` | **纯函数**：`resolve_volley(attacker, defender, ammo, posture) -> Dictionary` |
| `combat_director.gd` | 战斗流程：锁敌、齐射计时、四池扣血、帆舵损坏导致的航速/转向惩罚、接舷与撤离条件判定、胜负结算 |
| `enemy_ai.gd` | 状态机：patrol / chase / engage / flee |
| `spawn_director.gd` | 按配额生成与回收敌舰 |
| `loot_system.gd` | 掉落表抽取、入包 |
| `market_model.gd` | **纯函数**：价格计算、买卖、库存回归 |
| `navigation.gd` | AStarGrid2D 航线寻路、点击移动、导航跟随 |

### 3.3 UI 层（ui/）

`base_hud.gd`、`sea_hud.gd`、`market_panel.gd`、`repair_panel.gd`、`combat_overlay.gd`、`ticker.gd`、`rarity_frame.gd`（本阶段仅做灰/绿两档占位）。

### 3.4 数据层（scripts/data/ + data/）

Resource 类定义：`ship_def.gd`、`cannon_def.gd`、`commodity_def.gd`、`enemy_def.gd`、`port_def.gd`。

本期数据文件：

```
data/ships/    fishing_sloop.tres
data/cannons/  pound3_light.tres
data/commodities/ grain.tres, timber.tres, rum.tres, spice.tres
data/enemies/  pirate_scout.tres, reef_crab.tres
data/ports/    jadehaven.tres, map1_outpost.tres
```

---

## 4. 关键流程

### 4.1 战斗时序

```
玩家点击敌舰
  └─ CombatDirector.lock_target(enemy)
       ├─ EventBus.target_changed(enemy)
       └─ 每帧检查距离 <= cannon.range
             └─ 齐射计时器到期 → CombatResolver.resolve_volley(attacker, defender, ammo)
                   ├─ raw = guns × cannon.damage × quality × ammo.mult
                   ├─ hit = clamp(...)
                   ├─ 按弹药分配矩阵拆成 4 份：船体 / 风帆 / 舵机 / 船员
                   ├─ 应用 → EventBus.pool_changed(node, pool, value)
                   ├─ 帆归零 → 目标速度 0；舵归零 → 目标 turn_rate 0
                   ├─ 船员归零 → 俘获
                   └─ 船体归零 → 击沉 → LootSystem.roll_drop() → combat_finished
```

### 4.2 存档时机

- 进入母港 → 自动存档
- 离开母港 → 自动存档
- 手动点击存档 → 覆盖手动态
- 战斗结束 → 只更新内存，不落盘

---

## 5. 验收标准（阶段一完成的定义）

必须全部通过：

| # | 验收项 | 判定方式 |
|---|---|---|
| 1 | 启动进入主菜单，可开新游戏 | 目视 |
| 2 | 母港可点「出航」进入图 1 | 目视 |
| 3 | WASD 可操控船，点击海图可自动航行 | 目视 |
| 4 | 能锁定敌人，进入射程后自动开火 | 目视 + 战斗日志 |
| 5 | 链弹能在一轮内明显打低对方风帆，帆归零后敌舰速度变为 0 | 战斗日志 |
| 6 | 能击沉敌舰并获得金币与货物；葡萄弹打光船员可俘获 | 战斗日志 + 金币变化 |
| 7 | 战利品进入货舱，超载时提示 | 试玩 |
| 8 | 回港可修理（扣金币、耐久恢复） | 试玩 |
| 9 | 市场可买卖 4 种商品，价格随库存变化 | 连续买卖观察价格 |
| 10 | 退出重进，金币/货物/耐久/位置不丢 | 存档读写测试 |
| 11 | 无脚本报错（控制台无 ERROR） | headless 运行 + 交互运行 |
| 12 | 单场战斗平均 40～90 秒 | 计时 |

---

## 6. 工作量拆分（建议提交顺序）

| 步骤 | 内容 | 产出 |
|---|---|---|
| 1 | 项目骨架 + Autoload + 数据 Resource 类 + 3 个 .tres | 可启动空项目 |
| 2 | 玩家船运动 + 摄像机 + 海域地形 | 能开船 |
| 3 | 敌舰 + AI + 生成器 | 海上有敌人 |
| 4 | 战斗结算器 + 战斗浮层 + 四池损伤 | 能打沉敌人 |
| 5 | 战利品 + 货舱 + HUD | 有收益反馈 |
| 6 | 母港场景 + 修理 + 市场 | 闭环合拢 |
| 7 | 存档 + 主菜单 | 可中断续玩 |
| 8 | 手感打磨 + 数值首轮调整 | 可玩切片 |

---

## 7. 阶段一风险

| 风险 | 应对 |
|---|---|
| 观战太无聊 | 第 4 步做完立即自测；若观感差，优先加强"四池血条的视觉冲击 + 破帆/断舵/甲板减员的损伤表现 + 齐射画面"，**绝不加操作** |
| 船只手感差（转向像转盘） | 把 `turn_rate` 和加速度做成可热调参数，交互运行时用 `godot_command eval` 实时改 |
| 海图空旷 | 先加航标/浮标/沉船残骸等装饰几何，成本低、观感提升大 |
| 工作量低估 | 严格不做 Out of Scope 清单里的任何东西，尤其是"顺手加个船员系统" |
