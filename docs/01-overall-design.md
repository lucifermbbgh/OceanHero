# 碧海英豪 · 总体设计文档

| 项 | 内容 |
|---|---|
| 项目名 | 碧海英豪 / SeaHeroes |
| 版本 | **v0.2**（战斗部件化 / 时间轴 / 舰船三变体 修订） |
| 日期 | 2026-11-14 |
| 引擎 | Godot 4.7.2 / GDScript / GL Compatibility |
| 目标平台 | 桌面端（macOS 优先），1600×900 窗口，键鼠 |
| 形态 | 2D 单机，完全离线 |

---

## 1. 项目定位

一款 **2D 单机航海角色扮演游戏**：玩家操控一艘风帆战舰，在 9 片递进的海域上航行、战斗、贸易、
接任务、打 Boss，最终把一座孤岛经营成母港，并在终局海域立足。

它从 SeaFight（原中文名《海战英豪》，已于十多年前停服）中提炼 **非玩家互动内容**：
海图航行与冒险、NPC 海船、海盗与海怪、交易市场、船只装备配置、船只买卖、任务与悬赏。
剥离掉了原版的所有 MMO 部分（玩家对战、拍卖行、公会、付费墙、每日 CD）。

**核心差异点（相对原版手法的重构）**

1. **9 片海域的关卡化推进**：每片海域有唯一的 Boss 海盗与 Boss 海怪，击败后开启下一片海域。
2. **0 号图母港基地**：原版没有的建造/仓储/维修/招募系统，是本作的长期养成轴。
3. **纯观战部件损伤战斗**：锁定即自动对射，无走位、无瞄准、无姿态。船只由
   **船体 / 风帆 / 舵机 / 船员** 四个可分别击毁的系统构成，打帆则停、打舵则失去转向、
   杀光船员则整船俘获。玩家唯一的决策是**打谁、换什么弹、要不要接舷、要不要撤**。
4. **身份自由**：主角不固定为海盗，行为（劫掠 / 护航 / 贸易）塑造你被世界如何看待。

---

## 2. 核心体验与三大支柱

> **你既是一艘船，也是一个人。** 在九片海域里打捞财富与声望，把一座孤岛经营成母港，
> 最终在「王冠之海」留下自己的名字。

| 支柱 | 内容 | 玩家感受 |
|---|---|---|
| **舰船养成** | 10 级舰船（I～X）× 6 类装备 × 5 稀有度船员 | 从一条 1 门炮的渔船，到 120 门炮的一级战列舰 |
| **部件损伤炮战** | 锁敌 → 自动对射 → 打断帆舵 / 杀光船员 → 接舷俘获 | 纯观战，考验"带对船、配好炮、选对弹药" |
| **世界经营** | 港口行情套利 + 母港建设 + 三方声望 | 同一片海，可以是商路，也可以是猎场 |

### 2.1 舰船三变体

I～X 每一级都有三种船体。**通用型即商船定位**（载重最高、火力与航速最低），
海军型与海盗型需对应阵营声望解锁：

| 变体 | 定位 | 船体 | 炮数 | 航速 | 转向 | 载重 | 船员槽 | 价格 | 解锁 |
|---|---|---|---|---|---|---|---|---|---|
| **通用型** | 商船 · 贸易续航 | 110% | 90% | 90% | 95% | **130%** | 8 | 100% | 金币 + 船坞等级 |
| **海军型** | 火力与生存 | **130%** | **120%** | 85% | 90% | 80% | **12** | 150% | 海军声望 ≥ 500 × 等级 |
| **海盗型** | 速度与机动 | 80% | 90% | **125%** | **130%** | 70% | 9 | 130% | 黑帆声望 ≥ 500 × 等级 |

> 完整数值表与体验差异见 `02-systems-design.md` §5。

---

## 3. 玩家身份与自由度（三方声望）

主角不是固定职业。世界用三组独立声望记录你的行为，称号随之变化：

| 声望轴 | 亲善行为 | 敌视行为 | 主要收益 |
|---|---|---|---|
| **王权海军**（Royal Navy） | 击杀海盗、讨伐海怪、护航商船、缉拿通缉犯 | 劫掠商船、走私、攻击军舰 | 军舰购买权、港口通告、高额赏金 |
| **自由商会**（Merchant Concord） | 贸易额、运货任务、开辟航线 | 劫掠商船、毁约 | 买卖折扣、仓储扩容、大宗订单 |
| **黑帆同盟**（Black Sail） | 劫掠、走私、接黑市悬赏 | 击杀海盗、协助海军 | 黑市渠道、销赃、海盗不主动攻击 |

另有一条 **通缉度（-100 ～ +100）** 单轴，直接决定海军赏金猎人是否主动追捕你、以及哪些港口拒绝你入港。

**声望的三条获取途径**（细则见系统设计 §11.2）：

| 途径 | 说明 |
|---|---|
| **任务** | 完成阵营任务 → 该阵营 +80～400，敌对阵营 -40～200 |
| **捐赠** | 向阵营使节捐钱，1,000 金 = 10 声望，每阵营每周上限 50 声望 |
| **击杀敌对阵营船只** | 击沉海军船 → 黑帆 +15；击沉海盗 → 海军 +10、黑帆 −10；击沉商船 → 三轴连带变化 |

声望是**舰船变体的唯一解锁条件**（见下节）。

三条路线**可以混搭**，没有锁死的职业选择。称号按当前声望组合动态生成：
「守法商人」「私掠船长」「海军提督」「黑帆之王」——同一个存档里都可能出现。

---

## 4. 核心循环

```
        ┌──────────────── 母港（0 号图）────────────────┐
        │  修理 / 补货 / 招募 / 建造 / 接任务 / 换船   │
        └───────────────┬─────────────────────────────┘
                        │ 出航
                        ▼
        ┌──────────────── 海域（1～9 号图）─────────────┐
        │                                             │
        │   航行探索 ──► 遭遇（海盗/海怪/商船）         │
        │      ▲              │                       │
        │      │              ▼                       │
        │      │        自动炮战 / 接舷                 │
        │      │              │                       │
        │      │        ┌─────┴─────┐                 │
        │      │        ▼           ▼                 │
        │      │      胜利        沉没                  │
        │      │   战利品/货物   损失货物               │
        │      │        │      回港重来                 │
        │      │        ▼                              │
        │      └── 港口/任务结算 ──► 声望 · 金币 · 经验 │
        │                    │                        │
        │                    ▼                        │
        │           击破本图 Boss → 解锁下一张图        │
        └────────────────────┬────────────────────────┘
                             │
                             ▼
                    成长（船/炮/船员/基地）→ 去更远的海
```

**一次完整回合的预期节奏**

| 行为 | 时长 | 收益 |
|---|---|---|
| 单次出海（打 2～3 个目标） | 3～5 分钟 | 当前装备价值 2%～4% |
| 一场自动战斗 | 40～90 秒（可 2×/4× 加速） | 战利品 + 经验 |
| 贸易航次（A 港买 → B 港卖） | 5～8 分钟 | 货值 15%～30% |
| 一级舰船周期 | 约 30 次出海 + 1 次贸易航次 | 跨 1～2 个海域 |

---

## 5. 世界结构：10 张海图

| 图号 | 名称 | 英文 | 敌方等级 | 敌意行为 | Boss 海盗 | Boss 海怪 |
|---|---|---|---|---|---|---|
| **0** | **翡翠港**（母港） | Jadehaven | — | 无 | — | — |
| 1 | 浅湾水道 | Shallows | 1～3 | 不主动 | 「独眼」杰克 | 礁石巨蟹 |
| 2 | 珊瑚浅滩 | Coral Shoals | 3～6 | 不主动 | 「红胡」巴博萨 | 珊瑚海蛇 |
| 3 | 迷雾海峡 | Mist Strait | 6～10 | **海盗主动** | 「幽灵」范德 | 迷雾水母主 |
| 4 | 商道外海 | Trade Reaches | 10～15 | **海盗主动** | 「剪径者」莫尔干 | 黑鳍鲨王 |
| 5 | 黑鲸海域 | Black Whale | 15～21 | **海盗主动** | 「铁钩」卡尔 | 黑鲸王 |
| 6 | 风暴角 | Storm Cape | 21～28 | **海盗主动** | 「风暴」艾琳 | 雷暴海龙 |
| 7 | 骸骨礁群 | Skeleton Reefs | 28～36 | **海盗主动** | 「白骨」萨默斯 | 骸骨大王乌贼 |
| 8 | 深渊裂流 | Abyssal Rip | 36～45 | **海盗主动** | 「深渊」戴维 | 深渊利维坦 |
| 9 | 王冠之海 | Crown Sea | 45～60 | **海盗主动** | 「王冠」无名船长 | 九头蛇·涅柔斯 |

- **单图内无缝**：一张图 = 一个连续的可航行海域（约 8000×8000 px），无分块加载、无读条。
- **图间切换**：通过海域边缘的「航门」进入，短暂过渡（< 2 秒淡入淡出），位置锚定在对面图的入口处。
- **解锁规则**：击破图 N 的唯一 Boss（海盗或海怪任一）→ 图 N+1 航门开启。
- **0 号图**：只有母港「翡翠港」，无敌人、无战斗，是安全区。

每张图的内容配额（具体见系统设计文档 §2）：

| 类型 | 数量/图 | 说明 |
|---|---|---|
| 普通海盗船 | 12 | 巡逻队，掉落货物与金币 |
| 精英海盗船 | 4 | 小队旗舰，掉落装备 |
| 普通海怪 | 10 | 游荡，掉落材料 |
| 精英海怪 | 3 | 领地型，掉落稀有材料 |
| **Boss 海盗** | **1（唯一）** | 本图主线，击败解锁下一图 |
| **Boss 海怪** | **1（唯一）** | 本图主线，击败解锁下一图 |
| 中立商船 | 6 | 可劫掠（会影响声望）或护航 |
| 港口/锚地 | 2～3 | 本图内的补给点，可交易维修 |

---

## 6. 系统架构

### 6.1 分层

```
┌─ 表现层 ── 场景 / 特效 / 音效 / UI（Control）
├─ 玩法层 ── 航行 · 战斗流程 · 市场 · 装备 · 船厂 · 任务 · 悬赏 · 声望 · 基地
├─ 仿真层 ── 战斗结算器 · 价格模型 · AI 状态机 · 生成器（spawn director）
├─ 核心层 ── GameState（单一存档态）· EventBus（全局信号）· TimeService · SaveManager
└─ 数据层 ── Custom Resource：ShipDef / CannonDef / GearDef / CrewDef / CommodityDef /
              PortDef / EnemyDef / QuestTemplate / BuildingDef / AmmoDef
```

**架构铁律**

1. **数据与逻辑分离**：任何数值（船速、炮伤、商品基价）只能出现在 `data/*.tres`，脚本内不得硬编码。
2. **单一可变状态**：所有可存档数据集中在 `GameState`（一个 RefCounted/Resource），场景与 UI 只读、
   通过方法请求修改、通过 `EventBus` 收到变更通知。
3. **结算器纯函数化**：`CombatResolver`、`PriceModel` 不依赖节点树，输入输出皆为数据结构，
   以便在 `--headless` 下做单元测试与数值模拟。
4. **确定性**：一切随机走统一的 `RngService`（可设种子），保证测试可复现。

### 6.2 目录约定

```
scenes/
  boot/      启动、主菜单、读档界面
  base/      母港（建筑、港口 UI 入口）
  sea/       海域场景（地形、生成器、航门）
  ship/      玩家船、敌船、海怪
  combat/    战斗浮层、四池状态条、弹药切换、接舷/撤离面板
  ui/        共用控件（面板、列表、提示、稀有度边框）
scripts/
  core/      GameState, EventBus, SaveManager, DataRegistry, RngService, TimeService
  systems/   navigation, combat, economy, equipment, crew, quest, bounty, reputation, base
  ui/        各面板控制器
  data/      Resource 类定义（*_def.gd）
data/
  ships/ cannons/ gear/ crew/ commodities/ ports/ enemies/ quests/ buildings/ ammo/
tests/
  headless/  无头测试脚本（*_test.gd）
```

### 6.3 全局单例（Autoload）

| 名称 | 职责 |
|---|---|
| `GameState` | 当前存档的全部可变数据 |
| `EventBus` | 全局信号总线（`gold_changed`, `combat_finished`, `reputation_changed`...） |
| `DataRegistry` | 启动时加载全部 .tres，提供 `get_ship(id)` 等查询 |
| `RngService` | 确定性随机源 |
| `SaveManager` | 多存档位读写、原子写入、版本迁移 |
| `SceneRouter` | 场景切换与过渡 |

---

## 7. 技术选型与理由

| 需求 | 方案 | 理由 |
|---|---|---|
| 2D 海域地图 | `TileMapLayer` + 远景 Parallax | 原生支持，绘制调用少，可按图换图集 |
| 船只运动 | `CharacterBody2D` + 自定义转向惯性 | 需要碰撞与平滑转向，而非纯物理刚体 |
| 数据表 | Custom Resource（`.tres`） | 编辑器内可视化编辑、类型安全、可版本控制、可在测试中直接 new |
| 战斗结算 | 纯脚本 tick（`_physics_process` 驱动） | 无物理依赖，易测试；可 2×/4× 加速 |
| 存档 | JSON + schema 版本号 + 原子写（临时文件 → rename） | 可读可改、易迁移；避免半写坏档 |
| UI | Control + Theme（一处定义配色与字体） | 本项目 UI 密集，必须集中管理样式 |
| 测试 | `godot --headless --script` 自建断言 | 无外部依赖，可直接跑数值回归 |
| 音频 | 程序化占位音效优先，后期替换 | 不阻塞玩法开发 |

**为什么不用 C#**：预估总量 1.5～3 万行，GDScript 完全胜任；本项目瓶颈在设计而非性能。
若后期经济模拟或大规模 AI 计算吃紧，可**局部**用 C# 写结算器，无需整体迁移。

**Godot 是否担得起**：担得起。本项目同屏实体 < 100，2D 渲染与场景实例化无压力；
Godot 的 Custom Resource 与 headless 模式恰好是本项目最需要的两项能力（数据驱动 + 可测试）。

---

## 8. 核心数据契约

以下 10 个 Resource 是全项目的地基，字段一旦定稿，后续所有系统围绕它们展开。

### 8.1 ShipDef（舰船）

```
id: StringName              # "first_rate_120_standard"
display_name: String        # "一级战列舰（通用型）"
tier: int                   # 1..10  → 罗马数字 I..X
variant: StringName         # "standard" / "navy" / "pirate"
ship_class: String          # 渔船/沙船/长船/纵帆/横帆/护卫舰/战列舰
base_hp: int                # 船体池上限
base_speed: float           # 节（内部 px/s = 节 × 28）
turn_rate: float            # 度/秒
cargo_capacity: int
crew_capacity: int          # 同时决定船员池 = crew_capacity × 10
cannon_slots: int           # 总炮位数
guns_per_side: int          # 单侧齐射炮数
max_cannon_weight: int      # 可装备火炮的最大磅位等级
armor_base: int
price: int
build_materials: Dictionary
unlock_reputation: Dictionary  # {"royal_navy": 4000}  变体船的声望门槛
sprite_set: String
description: String
```

**战斗运行时池**（由上述基础属性派生，不写入定义）

```
sail_pool   = base_hp × 0.25
rudder_pool = base_hp × 0.15
crew_pool   = crew_capacity × 10
```

**船只实例**（存档中的 ship 对象）额外持有

```
station_port: StringName    # 停泊港口，决定换船限制
hull_hp / sail_pct / rudder_pct / crew_hp   # 战后残值
```

### 8.2 CannonDef（火炮）

```
id, display_name: StringName/String
pound_class: int            # 1..10（3磅 → 卡隆炮）
tier_weight: int            # 需要的炮位承载
damage: float
reload_seconds: float
range: float                # px
accuracy_mod: float         # 命中修正
muzzle_velocity: float      # 影响弹道表现
special: StringName         # "" / "chain" / "grape" / "fire"
price: int
```

### 8.3 GearDef（风帆 / 船舵 / 装甲 / 火枪 / 船首像 / 旗帜）

```
id, display_name
slot: StringName            # sail / rudder / armor / musket / figurehead / flag
stat_modifiers: Dictionary  # {"speed_pct": 0.12, "turn_pct": 0.05, "armor": 30, "boarding": 15}
rarity: int                 # 0 N / 1 R / 2 SR / 3 SSR / 4 UR
price: int
description: String
```

### 8.4 CrewDef（船员）

```
id, display_name
role: StringName            # helmsman / first_mate / gunner / lookout / boatswain / carpenter / surgeon / sailmaster
rarity: int                 # N/R/SR/SSR/UR
level: int
stats: Dictionary           # {"gunnery": 12, "seamanship": 8, "navigation": 5, "boarding": 10}
wage: int                   # 每日/每航次薪酬
hire_cost: int
portrait_key: String
```

### 8.5 CommodityDef（商品）

```
id, display_name
category: StringName        # food / raw / goods / luxury
base_price: int
volume: float               # 占用的货舱单位
legal: bool                 # false 为走私品（黑市）
```

### 8.6 PortDef（港口/大陆设施）

```
id, display_name
map_id: int
position: Vector2
services: Array[StringName] # ["repair", "market", "shipyard", "tavern"]
production: Dictionary      # {"timber": 1.4} 生产系数
demand: Dictionary          # {"spice": 1.6} 需求系数
stock: Dictionary           # 运行时库存
faction: StringName
```

### 8.7 EnemyDef（敌舰/海怪）

```
id, display_name
kind: StringName            # pirate / elite_pirate / sea_monster / elite_monster / boss_pirate / boss_monster / merchant / navy
map_id: int
level: int
based_on_ship: StringName   # 复用 ShipDef
hp_mult, damage_mult, speed_mult: float
ai_profile: StringName      # patrol / raider / predator / boss
loot_table: Array[Dictionary]
aggro_radius: float
xp_reward: int
```

### 8.8 BuildingDef（母港建筑）

```
id, display_name
max_level: int
effect_per_level: Dictionary  # {"storage": 200, "repair_discount": 0.04}
cost_per_level: Array[Dictionary]
build_time_per_level: Array[float]
requires: Array[StringName]   # 前置建筑
```

### 8.9 QuestTemplate（任务模板）

```
id, display_name
type: StringName            # bounty / escort / transport / hunt / trade / story
giver_faction: StringName
params: Dictionary          # 目标数量、目标类型、目的地
reward_gold: int
reward_xp: int
reward_reputation: Dictionary
difficulty: int
```

### 8.10 AmmoDef（弹药）

```
id, display_name
damage_mult, range_mult, accuracy_mult: float
special_effect: StringName  # "" / "rigging"（链弹破坏帆）/ "crew"（葡萄弹伤船员）/ "fire"（燃烧）
price_per_shot: int
```

---

## 9. 开发阶段规划

| 阶段 | 目标 | 主要交付 | 验收标准 |
|---|---|---|---|
| **一** ✅ | 垂直切片：一条完整闭环跑通 | 母港（简化）+ 1 号图 + 自动战斗 + 战利品 + 修理/卖货 + 存档 | **已完成**，见 `05-test-report-phase-1.md` |
| **二** ✅ | 经济、养成与时间轴 | 市场行情、装备系统、船厂买卖、船员招募、**游戏内时间与周结算** | **已完成**：时间轴 / 周结算 / 装备 / 船厂（三变体 + 声望门槛）/ 10 级火炮 / 船员与岗位加成。见 `05-test-report-phase-2.md` |
| **三** ✅ | 母港建设 | 8 座建筑 + 周产出 + 建造队列 + 船只调拨 | **已完成**：8 座建筑可建可升、周产出与建造队列生效、六项效果接入、交易所四标签、哨站跨港调拨。见 `05-test-report-phase-3.md` |
| **四** ✅ | 世界内容 | 10 张图、18 个 Boss、任务生成器、悬赏与通缉 | **已完成**：9 张海域逐图推进、18 个 Boss（装备特异化）、5 类任务、通缉与赏金猎人、存档位 UI。见 `05-test-report-phase-4.md` |
| **五** ✅ | 系统收口 | 声望三轴、战功商店、通缉保释、通关结算、帮助面板 | **已完成**（音效与成就按需推迟）。见 `05-test-report-phase-5.md` |
| **六** ✅ | Demo 交付 | 二轮平衡、稳定性压测、完整回归、交付文档 | **已完成**：`08-demo-guide.md`（说明）+ `09-playtest-record.md`（64 条待测用例）。|

阶段一详细设计见 `03-phase-1-design.md`。

---

## 10. 主要风险与对策

| 风险 | 表现 | 对策 |
|---|---|---|
| **范围蔓延** | 10 个子系统同时开工，全部半成品 | 严格按阶段推进；阶段未验收不开新系统 |
| **观战无聊** | 玩家只是看着数字跳 | 四池（船体/帆/舵/船员）分别显示 + 损伤可视化（破帆、断舵、甲板减员）；弹药选择 = 打哪个系统，这是唯一但有意义的决策；提供 2×/4× 时间加速 |
| **数值通胀** | 后期钱多到没意义，或卡在某个 Boss | 阶段二必须交付经济模拟脚本（headless 跑 1000 次出海）并出收益曲线图 |
| **UI 工作量爆炸** | 40% 工时耗在界面 | 阶段一即建立 Theme 与通用控件库，所有面板复用 |
| **内容产能** | 18 个 Boss 需要独特美术 | 采用"同族换色 + 尺寸放大 + 独特部件"策略，风格统一优先于独特 |
| **存档兼容** | 后期改结构导致旧档失效 | 从第一天就带 schema 版本号与迁移函数 |

---

## 11. 已确认 / 待确认

### 11.1 已确认（v0.2 定稿）

| # | 事项 | 结论 |
|---|---|---|
| 1 | 战斗形态 | 纯观战自动对射，无姿态、无加速、无手动瞄准 |
| 2 | 部件系统 | 船体 / 风帆 / 舵机 / 船员 四池，打帆停船、打舵失转向、船员清零被俘 |
| 3 | 接舷 | 仅目标船体 ≤ 10% 时开放，观战结算船员生命 |
| 4 | 撤离 | 仅在己方风帆与舵机完好时可行 |
| 5 | 时间 | 流动可暂停，1 游戏日 = 24 现实秒，**每周结算一次**产出/建造/市场/任务 |
| 6 | 离线产出 | **取消**。游戏关闭即时间停止 |
| 7 | 舰船 | 通用 / 海军型 / 海盗型 三变体，变体由声望解锁 |
| 8 | 声望获取 | 任务 + 捐赠（1,000 金 = 10 点，周上限 50）+ 击杀敌对阵营船只 |
| 9 | 编队 | 不做。单船操控，库存切换 |
| 10 | 换船限制 | 必须在港口，且只能换该港停泊的船，无跨港调拨 |
| 11 | 稀有度配色 | 灰 / 海蓝 / 罗马紫 / 黄金 / 六色流光 |
| 12 | 死亡惩罚 | 不删档；沉船损失货物，所在港口无船时赠 I 级通用渔船 |
| 13 | 商会船型 | **不做专属船型**，通用型即商船定位（载重 130%、火力 90%、航速 90%、船体 110%） |
| 14 | 船员槽位 | 通用 8 / 海军 12 / 海盗 9；指挥岗（舵手/大副/水手长/操帆长）永不超过 1 人 |
| 15 | 变体专属岗位 | 海军型「征税官」（进港征税 + 声望）、海盗型「突击队长」（接舷伤害 +25%） |
| 16 | 海怪 | 独立战斗模型（躯体 + 肢体 + 狂怒），不能接舷、不能俘获、链弹无效；产出**材料与图纸**，是 UR 装备的唯一材料来源 |
| 17 | 奇幻内容 | 分三层：图 1～6 纯历史、图 7～8 传说暗示、图 9 明确超自然。魔法船为 Boss 独占不可获得；9 件 UR 材料装备；3 名魔法船员 |
| 18 | 交易所 | 母港专属，4 个标签页：行情 / 远洋订单 / 大宗交易 / 期货 |
| 19 | 其余 | 母港「翡翠港」、终局为击破 9 图 Boss 后自由沙盒、5+1 存档位、音效占位 |
| 20 | 碰撞 | 船↔船 / 船↔怪 / 船↔宝藏**无碰撞**；岛屿用软约束排斥；浅滩只减速；点击航线做一次绕行。无人需要 A* 寻路 |
| 21 | 热参数 | 分两层：常量资源化（阶段二）+ 公式`Expression`化（阶段三，仅限 8～10 个高频公式） |
| 22 | 货币 | **金币 + 战功**双货币。不做金银铜（那是显示问题），不做珍珠/勋章（那是 F2P 付费设计）。战功不可购买、不可兑换金币 |

### 11.2 待确认（不阻塞阶段一）

1. **奇幻内容的分层方案**是否认可（§19，01 文档 §11.1 第 17 条）。
   若你希望魔法从更早期就出现，我只需调整"第二/三层的起始海域"，系统设计不用重写。
2. **母港「翡翠港」与 9 片海域命名**是否沿用草案。
3. **海怪材料是否还要有第二个用途**（目前只用于 UR 装备，可考虑也用于高级船只建造）。
