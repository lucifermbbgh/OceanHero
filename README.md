# 碧海英豪 (SeaHeroes)

> 版本 **0.7.0-alpha** · 文档总览 [docs/00-index.md](docs/00-index.md)

2D 单机航海 RPG。驾驶风帆战舰穿行九片海域，观战式部件损伤炮战、港口贸易、船员招募与母港建设，
三条身份路线（海盗 / 海商 / 海军提督）由玩家行为自然塑造。

- 类型：2D 航海角色扮演 · 贸易 · 舰船养成 · 基地建设
- 引擎：Godot 4.7.2 / GDScript / GL Compatibility
- 平台：桌面（macOS / Windows / Linux），键鼠操作
- 语言：简体中文
- 网络：完全离线，无任何联网依赖
- 参考：SeaFight（原《海战英豪》网页游戏）、大航海时代系列、海商王

## 一句话玩法

> 你既是一艘船，也是一个人。在九片海域里打捞财富与声望，把一座孤岛经营成母港，
> 最终在「王冠之海」留下自己的名字。

## 目录结构

    SeaHeroes/
    ├── README.md              本文件
    ├── docs/                  全部设计、测试与说明文档
    │   ├── 01-overall-design.md      总体设计（定位、循环、世界结构、架构、数据契约、阶段规划）
    │   ├── 02-systems-design.md      系统详细设计（航行/战斗/养成/经济/任务/基地等全部子系统）
    │   ├── 03-phase-1-design.md      阶段一（垂直切片）详细设计
    │   ├── 04-test-plan.md           测试方案与验收标准
    │   └── 06-design-changelog.md    设计变更记录（含被否决方案）
    ├── project.godot
    ├── scenes/                场景（base 母港 / sea 海域 / combat 战斗 / ui 界面）
    ├── scripts/               GDScript（core / systems / ui）
    ├── data/                  数据表（Custom Resource：船只、火炮、商品、敌人、任务、建筑）
    └── assets/                美术与音频资源

## 运行

    # 交互运行（推荐通过 agent 工具 godot_run_project 启动）
    godot --path "$HOME/app/Godot/projects/SeaHeroes"

    # 无头验证
    godot --headless --path "$HOME/app/Godot/projects/SeaHeroes" --quit-after 120

## 当前状态

**阶段一（垂直切片）已完成；阶段二前两批交付完成**。

可运行的闭环：主菜单 → 母港 → 出海 → 锁定敌舰自动炮战 → 击沉/俘舷 → 战利品入舱 →
回港修理与交易 → 存档读档。已叠加：**双货币（金币 + 战功）、游戏内时间轴与周结算、
岛屿软约束避障、热参数配置与 F5 热重载、装备穿戴与船厂（三变体舰船 + 声望门槛）、
10 级火炮换装、船员招募与岗位加成、母港 8 座建筑与周产出、
交易所四标签（行情/远洋订单/大宗/期货）、哨站跨港调拨、
**9 张递进海域与关卡推进、18 个三阶段 Boss（9 件独有装备 + 9 名独有船员）、
5 类任务（讨伐/贸易/运输/护航/采集）、通缉与赏金猎人、5+1 存档位 UI、
声望三轴与战功商店、通关结算与帮助面板**。

- 自动化测试：单元 65 项 + 集成 240 项，全部通过
- 测试报告：`docs/05-test-report-phase-1.md` ~ `05-test-report-phase-4.md`
- 平衡报告：`docs/07-balance-report.md`（含可复跑的出海模拟器）
- **Demo 说明**：`docs/08-demo-guide.md`
- **实测记录表**：`docs/09-playtest-record.md`（案例待回填）
- **构建与游玩**：`docs/10-build-and-play.md`（macOS / Windows 导出与运行说明）
- 下一步：真人试玩 → 按实测结果调优 → Boss 特异性深化 → 各图港口 → 音效 → 美术替换

## 操作

| 场景 | 操作 |
|---|---|
| 主菜单 | 鼠标点击新游戏 / 读取存档 |
| 母港 | 左侧按钮：修理 / 市场 / 船厂 / 酒馆 / 建设 / 交易所 / 任务板 / 出航 / 保存 / 主菜单 |
| 海域 | `W`/`S` 前后，`A`/`D` 转舵，左键点海图自动航行，左键点敌舰锁定（锁定后自动开火），`E` 在航门返回母港 / 在哨站入港 |
| 战斗 | 底部按钮切换弹药（实心/链弹/葡萄弹）；目标船体 ≤10% 时「接舷」可用；帆舵俱在时「撤离」可用 |

## 文档阅读顺序

1. `docs/01-overall-design.md` — 先看这个，理解整体要做什么
2. `docs/02-systems-design.md` — 每个子系统的具体规则与数值
3. `docs/03-phase-1-design.md` — 第一阶段要写哪些代码
4. `docs/04-test-plan.md` — 怎么算做对了
