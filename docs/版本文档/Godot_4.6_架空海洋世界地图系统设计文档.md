# Godot 4.6 架空海洋世界地图系统设计文档

**版本：** 1.0  |  **日期：** 2026-11-21  |  **目标环境：** Godot 4.6 / GDScript / 2.5D / 约 100 个区域

> 本文是面向实施的技术设计说明。所有 GDScript 代码均为首版骨架，集成到项目时仍需按实际节点路径、资源名称和业务条件调整。

## 1. 文档概述

本文定义一套用于 Godot 4.6 单机游戏的架空海洋世界地图系统。地图采用现有背景图片作为美术底图，以不规则 Polygon 划分约 100 个可交互区域；玩家可以查看海域、悬停高亮、选择目标、查看可通行路径，并在游戏场景中通过出口触发器从当前海域切换到相邻海域。

本系统不以模拟真实板块运动、侵蚀、河流或地质演化为目标。区域边界是游戏设计数据，而不是自然地理模拟结果。系统的核心是“地图空间分区 + 显式通行图 + 场景切换协议”。

| 项目项 | 确定值 / 设计假设 |
| --- | --- |
| 引擎 | Godot 4.6，GDScript |
| 地图形态 | 2.5D 观感；底层仍使用二维地图坐标和二维区域多边形 |
| 区域规模 | 约 100 个区域，支持后续扩展至数百个 |
| 美术资源 | 已有完整世界地图背景图片；区域边界需在地图编辑器中绘制 |
| 区域表示 | Tiled Polygon Object → 标准化 JSON → Godot Polygon2D / CollisionPolygon2D |
| 路径规则 | 显式有向连接；双向连接通过两条有向 Transition 表示 |
| 游戏模式 | 实际航行时必须经过场景出口；世界地图主要用于查看、选区与规划路线 |

> **关键决策：** 世界地图上的区域相邻关系与游戏通行规则分开保存。两个 Polygon 共享边界，只表示“几何上相邻”；是否允许航行，必须由 Transition 数据明确授权。

## 2. 目标、范围与非目标

### 2.1 目标

- 将一张完整的海洋世界背景图切分为约 100 个不规则区域。
- 鼠标悬停时高亮区域填充和边缘；离开时恢复；当前区域、选中区域和可到达区域拥有不同视觉状态。
- 点击区域可选中并展示名称、类型、危险度、解锁状态等信息。
- 基于区域连接图计算路径，并在世界地图上可视化路线。
- 在实际游戏场景中，玩家船只触发区域出口后，校验连接规则、加载目标区域场景，并放置到目标入口出生点。
- Agent 能读取、创建、修改、校验区域和连接数据；修改先进入暂存区，通过校验后再构建运行时数据。

### 2.2 本期不做

- 不模拟板块碰撞、地壳演化、侵蚀、河流、真实洋流或完整气候系统。
- 不要求地图采用真实经纬度、球面投影或 GIS 坐标。
- 不将世界地图点击直接等同于无条件传送；探索模式下的实际跨区仍通过场景出口执行。
- 不在第一阶段制作完整的可视化地图编辑器；先使用 Tiled 作为区域绘制工具。

## 3. 总体架构

采用四层职责划分。编辑阶段与运行阶段之间通过标准化 JSON 文件交接，避免游戏逻辑直接依赖 Tiled 文件格式或外部导入插件。

| 层次 | 组成 | 职责 | 数据 / 产物 |
| --- | --- | --- | --- |
| 美术表现层 | 世界地图背景图、装饰图层、光影、海浪、标签 | 提供 2.5D 观感；不承担区域真值 | PNG / WebP / Godot Texture |
| 区域几何层 | Tiled Object Layer + Polygon | 定义区域边界、区域 ID 和基础属性 | world_regions.tmj |
| 导航逻辑层 | Transition Graph + 构建/校验工具 | 定义有向通行关系、路径成本、出口和入口映射 | world_connections.json、world_map.json |
| 游戏运行层 | Godot Node2D、Polygon2D、Area2D、Line2D、Autoload | 显示区域、响应输入、寻路、场景切换 | 运行时场景与存档状态 |

### 3.1 推荐数据流

```text
现有世界地图背景图
        │
        ├── Inkscape / Krita 等：美术修改（可选）
        │
        ▼
Tiled：world_regions.tmj
  ├── Background 图层（参考底图）
  ├── Regions 对象图层（Polygon + 属性）
  └── Labels / POI（可选）
        │
        ├────────────── world_connections.json
        │                 （显式通行关系）
        ▼
Map Pipeline（Python CLI / Agent 工具）
  ├── 读取 Tiled JSON
  ├── 规范化坐标和区域属性
  ├── 计算几何邻接候选
  ├── 校验 Polygon / Transition / 场景引用
  └── 输出标准化 world_map.json
        │
        ▼
Godot 4.6 Runtime
  ├── WorldRegionManager（区域数据和 Graph）
  ├── WorldMapScreen（地图交互与路线展示）
  ├── RegionVisual（单区渲染和命中）
  ├── RegionExitGate（游戏场景出口）
  └── RegionTravelManager（场景切换和出生点）
```

### 3.2 核心原则

- 背景图片是视觉底图；Polygon 是交互边界；Graph 是通行规则；Scene 是实际可玩区域。四者通过稳定 ID 关联。
- 所有地图坐标统一使用背景图片像素坐标，禁止在不同文件中混用缩放后的视口坐标。
- 运行时只读取构建后的 world_map.json，不直接解析 Tiled 文件，也不依赖 YATI 才能启动游戏。
- 地图几何可自动建议邻接候选，但最终是否能通行由人工或 Agent 写入的 Transition 决定。

## 4. 2.5D 世界地图表现设计

### 4.1 视觉层级

| 视觉层 | Godot 节点建议 | 说明 |
| --- | --- | --- |
| 底图 | Sprite2D | 使用现有完整世界地图图片；地图坐标原点与图片左上角一致。 |
| 海洋氛围层 | Sprite2D / GPUParticles2D / ShaderMaterial | 可加入轻微海面纹理、光斑、漂浮颗粒；纯装饰，不参与命中检测。 |
| 岛屿阴影 / 高光 | Sprite2D / Polygon2D | 营造浮雕、海岸层次和轻微高度感。 |
| 区域填充 | Polygon2D | 默认低透明度填充；悬停、选中、当前区域切换颜色。 |
| 区域边缘 | Line2D | 绘制区域轮廓；悬停时提高亮度、宽度或添加发光材质。 |
| 航线 / 连接 | Line2D / Path2D | 显示已选路径；可用动画纹理或移动粒子表现航行方向。 |
| 标记 / 标签 | Sprite2D / Label / Control | 港口、岛屿名称、玩家位置、危险标志等。 |
| 固定 UI | CanvasLayer + Control | 区域信息面板、筛选器、路径详情、返回按钮等。 |

### 4.2 坐标与视差约束

地图背景、区域 Polygon、区域轮廓、路线和地图标记必须处于同一个 MapContent 坐标系中，并一起受 Camera2D 的缩放和平移影响。不要让区域 Polygon 或可交互底图单独使用 Parallax2D，否则地图装饰和命中区域会产生错位。

可以对纯装饰的云层、海面光斑、远景雾层使用轻微视差，但交互底图及区域几何必须保持严格对齐。若实际 2.5D 指的是带透视的 3D 相机，而非 2D 视差风格，则需在后续阶段改用 SubViewport / 3D 平面方案；本设计暂按“2D 地图 + 分层深度效果”实现。

## 5. Godot 场景结构

### 5.1 世界地图主场景

```text
WorldMapScreen.tscn
WorldMapScreen (Node2D)              [WorldMapScreen.gd]
├── CameraRig (Node2D)
│   └── Camera2D
├── MapContent (Node2D)
│   ├── Background (Sprite2D)
│   ├── AtmosphereLayer (Node2D)     # 纯装饰，可选
│   ├── RegionFillLayer (Node2D)
│   ├── RegionOutlineLayer (Node2D)  # 或由 RegionVisual 自己绘制
│   ├── RouteLayer (Node2D)
│   ├── MarkerLayer (Node2D)
│   └── RegionLayer (Node2D)         # 动态实例化 RegionVisual
└── HUD (CanvasLayer)
    ├── RegionInfoPanel (Control)
    ├── NavigationPanel (Control)
    ├── LegendPanel (Control)
    └── MapControls (Control)

RegionVisual.tscn
RegionVisual (Area2D)                [RegionVisual.gd]
├── Fill (Polygon2D)
├── HitShape (CollisionPolygon2D)
└── Outline (Line2D)
```

### 5.2 主场景节点职责

| 节点 | 职责 / 配置 |
| --- | --- |
| WorldMapScreen | 加载地图数据，实例化区域视觉节点，维护 hover / selected / current 状态，接收 UI 命令。 |
| Camera2D | 地图缩放和平移；地图输入坐标必须通过正确的 Canvas/Node 变换转换。 |
| Background | 承载现有背景图，建议 Texture Filter 与缩放方式在全项目统一。 |
| RegionLayer | 每个区域实例化一个 RegionVisual；约 100 个节点规模可接受。 |
| RouteLayer | 绘制路径线、方向箭头或航线粒子。 |
| HUD | 固定在屏幕空间，不随地图缩放；显示区域信息和导航按钮。 |

### 5.3 区域状态模型

| 状态 | 建议表现 | 说明 |
| --- | --- | --- |
| default | 轻微透明填充，低对比边缘 | 默认区域。 |
| hovered | 边缘高亮、填充增强 | 鼠标指向。 |
| selected | 明显描边、信息面板展示 | 用户当前选中的目标区域。 |
| current | 持续高亮 + 玩家标记 | 玩家当前所在区域，不因鼠标移开而消失。 |
| reachable | 辅助颜色或边缘标记 | 从当前区域存在直接可用 Transition。 |
| locked | 降低亮度 / 锁图标 | 因等级、任务或剧情条件暂不可进入。 |

hovered、selected、current、reachable 是独立状态，不应使用单一布尔值互相覆盖。例如当前区域同时被鼠标悬停时，离开鼠标后仍应保留 current 样式。

## 6. Tiled 地图制作与导入方案

### 6.1 工具定位

Tiled 负责编辑区域边界和区域属性。建议将现有背景图作为 Tiled 的参考 Image Layer，锁定该图层避免误移动；实际游戏中仍由 Godot Sprite2D 加载背景图片。这样 Tiled 是编辑工具，而不是运行时依赖。

| 文件 / 图层 | 内容 | 约束 |
| --- | --- | --- |
| world_regions.tmj | Tiled JSON 地图源文件 | 作为几何编辑源；纳入 Git。 |
| Background | 完整世界地图图片的 Image Layer | 只作对齐参考；锁定图层。 |
| Regions | Object Layer，每个可玩区域一个 Polygon Object | 对象 class/type 设为 Region；必须有唯一 region_id。 |
| Labels（可选） | 点对象或文本对象 | 用于名称标签或 POI，不影响区域通行逻辑。 |
| world_connections.json | 有向 Transition 列表 | 人工或 Agent 管理的游戏通行关系，不从几何相邻直接自动放行。 |

### 6.2 地图尺寸与坐标约定

- 以背景图片的原始像素宽高作为 world.width / world.height，例如 4096 × 2304。实际项目应读取图片真实尺寸，不在文档中硬编码示例值。
- Tiled 使用 Orthogonal、Finite Map；tilewidth / tileheight 可按 32 或 64 设置，它们只用于编辑器网格，不改变对象坐标的像素语义。
- Tiled Polygon Object 的 x/y 是对象原点，polygon 数组中的点是相对对象原点的坐标。导出时需转换为绝对地图坐标：absolute_point = object_position + polygon_local_point。
- 第一版禁止 Polygon Object 旋转；如后续开放旋转、缩放或 Group Layer offset，转换器必须按 Tiled 变换规则完整处理。
- Polygon 顶点不必重复首点；导出到 Godot 后由 Polygon2D / CollisionPolygon2D 自动闭合。至少 3 个有效顶点。

### 6.3 Region 对象属性约定

| 属性名 | 类型 | 必填 | 示例 / 说明 |
| --- | --- | --- | --- |
| region_id | string | 是 | sea_001；稳定、唯一、不可因显示名称修改而改变。 |
| display_name | string | 是 | Azure Sea；玩家看到的名称。 |
| region_type | string | 是 | ocean / island_sea / port_area / special。 |
| danger_level | int | 否 | 0～5，或按项目约定的等级。 |
| scene_path | string | 否 | res://scenes/regions/sea_001.tscn。非可玩区域可留空。 |
| map_anchor_x/y | float | 否 | 用于路线节点定位、标签定位；不提供时由构建工具计算质心近似值。 |
| unlock_flag | string | 否 | 解锁条件标识；具体判断由游戏业务层实现。 |

### 6.4 导出和转换步骤

1. 在 Tiled 中打开 world_regions.tmj，检查 Background 图片与实际游戏底图尺寸、缩放一致。
2. 在 Regions 对象层绘制 Polygon；每个对象设置 region_id、display_name、region_type 等属性。
3. 通过 File → Export As 导出 JSON（.tmj）。Tiled JSON 支持对象 polygon 顶点和自定义 properties 字段。
4. 运行 map_pipeline build：读取 .tmj 与 world_connections.json，转换为统一坐标、规范字段、计算锚点并执行校验。
5. 生成 res://data/generated/world_map.json；Godot 运行时只读取该文件。
6. 在 Godot 中运行 WorldMapScreen 测试悬停、点击、高亮、路线和缩放。

### 6.5 YATI 插件策略

YATI（Yet Another Tiled Importer）可以作为可选的 Godot 编辑器导入工具，用于查看 Tiled 地图导入后的节点结构，或在后续需要导入更多 Tiled 图层时使用。当前项目建议先不让运行时逻辑依赖 YATI：自定义 Map Pipeline 读取 Tiled JSON 并输出游戏自己的 world_map.json，依赖更少、数据契约更稳定。

截至本设计文档编写时，YATI 仓库说明列出的版本 2.2.7 要求 Godot 4.3.0 或更高，并注明在 Godot 4.6.1 与 Tiled 1.12 上测试。你的环境为 Godot 4.6，因此版本条件看起来匹配，但仍建议在项目确切的 Godot 4.6.x 补丁版本上做最小导入验证，并锁定插件版本。YATI README 也记录了多地图导入可能冻结的已知问题及关闭多线程导入的建议；如果启用，应按仓库说明配置并实测。

> **推荐结论：** 主路线：Tiled JSON + 自定义 Map Pipeline + Godot 原生运行时。YATI 仅作为可选预览/导入辅助，不作为发布游戏的硬依赖。

## 7. 标准化地图数据模型

### 7.1 world_map.json 顶层结构

```json
{
  "schema_version": 1,
  "world": {
    "id": "ocean_world",
    "name": "The Azure Expanse",
    "width": 4096,
    "height": 2304,
    "background_path": "res://art/world_map/world_ocean.png",
    "start_region_id": "sea_001"
  },
  "regions": [
    {
      "id": "sea_001",
      "display_name": "Azure Sea",
      "region_type": "ocean",
      "polygon": [[120, 180], [430, 150], [510, 380], [260, 520]],
      "map_anchor": [300, 320],
      "scene_path": "res://scenes/regions/sea_001.tscn",
      "properties": {
        "danger_level": 1,
        "unlock_flag": ""
      }
    }
  ],
  "transitions": [
    {
      "id": "sea_001_to_sea_002",
      "from_region": "sea_001",
      "to_region": "sea_002",
      "enabled": true,
      "travel_cost": 1.0,
      "exit_gate_id": "east_gate",
      "entry_spawn_id": "west_spawn",
      "requirements": {}
    }
  ]
}
```

### 7.2 字段语义

| 字段 | 语义 / 约束 |
| --- | --- |
| schema_version | 数据结构版本；字段有不兼容变化时递增。 |
| world.width / height | 背景地图的原始像素尺寸；Polygon 坐标必须处于此范围内。 |
| background_path | Godot 可加载的 res:// 资源路径；发布导出时必须确保图片被包含。 |
| regions[].id | 全局稳定 ID，建议小写字母、数字和下划线；不得重复。 |
| regions[].polygon | 绝对地图坐标的二维点数组；第一版只支持单一外环，不支持洞和 MultiPolygon。 |
| regions[].map_anchor | 路线连线和地图标签参考点，不参与区域命中。 |
| regions[].scene_path | 对应的游戏海域场景；非可玩区域可为空。 |
| transitions[] | 有向通行边；双向必须显式建立反向记录。 |
| exit_gate_id / entry_spawn_id | 当前海域场景出口触发器 ID 与目标海域出生点 ID。 |
| travel_cost | 路径规划权重，必须大于 0；可代表航行时间、距离或综合成本。 |
| requirements | 任务、等级、道具、天气等条件的扩展容器；第一阶段可先为空对象。 |

### 7.3 为什么 Transition 使用有向边

几何相邻不等于一定可以航行；有时存在单向洋流、剧情封锁、海峡管制或特殊航线。因此，Graph 采用有向边。若 A 与 B 双向通行，则分别配置 A→B 和 B→A 两条记录，各自拥有独立的 exit_gate_id 和 entry_spawn_id。这样不会把一个方向的场景出口错误复用到另一个方向。

## 8. 邻接关系与路径算法

### 8.1 几何邻接候选

构建工具对每对区域 Polygon 检查边界共享长度。约 100 个区域最多只有 4,950 对区域组合，离线构建时可采用简单两两检查；更大规模再引入空间索引。若两个 Polygon 共享的线段总长度超过 min_shared_boundary_px，即生成“邻接候选”。仅在一个顶点接触不算相邻。

推荐在 Python 构建工具中使用 Shapely 做 Polygon validity、intersection 和 boundary overlap 检查；若不希望增加依赖，可以在第一版采用线段共线且重叠长度大于阈值的几何算法。无论使用何种实现，运行时都只读预先确认的 transitions。

### 8.2 自动候选与最终通行分离

| 情况 | 几何判定 | Graph 处理 |
| --- | --- | --- |
| A、B 共享一段边界 | 邻接候选 | 由设计者 / Agent 决定是否创建 A→B、B→A。 |
| A、B 只在一点接触 | 不视为邻接 | 默认不生成连接；如是桥、传送门，需显式特殊 Transition。 |
| A、C 不相邻但有传送门 | 非邻接 | 允许显式添加带 type=portal 的连接，并标明例外原因。 |
| A、B 相邻但被剧情封锁 | 邻接候选 | Transition 可存在但 enabled=false，或通过 requirements 控制。 |

### 8.3 路径算法

本项目区域数量约 100，建议第一版使用 Dijkstra。它支持每条 Transition 不同 travel_cost，时间复杂度对本项目规模足够。若只关心经过区域数量，可使用 BFS；若未来引入坐标启发和大量区域，再考虑 A*。

- find_path(start, goal)：返回区域 ID 序列，例如 [sea_001, sea_002, sea_017]。
- get_neighbors(region_id)：返回当前所有已启用的直接可达区域。
- can_travel(from, to)：只检查是否存在启用且满足条件的直接 Transition。
- 路线展示使用各区域 map_anchor 连接；该折线仅用于世界地图导航视觉，不代表实际船只航行轨迹。

> **游戏规则约束：** 世界地图的寻路结果表示推荐区域序列，不允许在普通航行模式下直接跨越中间区域。船只仍需在当前海域中移动到对应出口触发器，再进入下一海域。若未来增加快速旅行，应使用独立的 fast_travel 规则和 UI。

## 9. Godot 运行时脚本设计

### 9.1 Autoload 与脚本清单

| 脚本 / 场景 | 类型 | 职责 |
| --- | --- | --- |
| WorldRegionManager.gd | Autoload | 加载标准 JSON；维护 Region、Transition 字典；邻接查询和 Dijkstra。 |
| RegionTravelManager.gd | Autoload | 执行实际区域切换；保留目标 entry_spawn_id；处理加载失败。 |
| WorldMapScreen.gd | Node2D | 实例化区域视觉节点，维护交互状态，展示路线。 |
| RegionVisual.gd | Area2D | Polygon 填充、碰撞命中、悬停和点击信号。 |
| RegionExitGate.gd | Area2D | 游戏场景中的边界出口；调用通行检查并触发切换。 |
| RegionSpawnPoint.gd | Marker2D | 提供目标场景入口出生位置。 |

### 9.2 RegionVisual.gd

RegionVisual 使用 Polygon2D 负责视觉填充，CollisionPolygon2D 负责鼠标命中；Area2D 响应 mouse_entered、mouse_exited 和 input_event。Godot 4.6 的 Area2D 可使用 CollisionPolygon2D 定义二维区域，CollisionPolygon2D 支持凹多边形。

```gdscript
extends Area2D
class_name RegionVisual

signal hovered(region_id: String)
signal unhovered(region_id: String)
signal clicked(region_id: String)

var region_id: String = ""

@onready var fill: Polygon2D = $Fill
@onready var hit_shape: CollisionPolygon2D = $HitShape
@onready var outline: Line2D = $Outline

func _ready() -> void:
    input_pickable = true
    collision_layer = 1
    collision_mask = 0
    mouse_entered.connect(_on_mouse_entered)
    mouse_exited.connect(_on_mouse_exited)
    input_event.connect(_on_input_event)

func configure(data: Dictionary) -> void:
    region_id = str(data.get("id", ""))
    var points := PackedVector2Array()
    for pair in data.get("polygon", []):
        if pair is Array and pair.size() >= 2:
            points.append(Vector2(float(pair[0]), float(pair[1])))
    if points.size() < 3:
        push_error("Invalid polygon for region: %s" % region_id)
        return
    fill.polygon = points
    hit_shape.polygon = points
    var closed_points := points.duplicate()
    closed_points.append(points[0])
    outline.points = closed_points
    set_visual_state(false, false, false, false)

func set_visual_state(is_hovered: bool, is_selected: bool,
        is_current: bool, is_reachable: bool) -> void:
    if is_current:
        fill.color = Color(0.95, 0.68, 0.22, 0.28)
        outline.default_color = Color(1.0, 0.84, 0.42, 1.0)
        outline.width = 4.0
    elif is_selected:
        fill.color = Color(0.25, 0.75, 1.0, 0.30)
        outline.default_color = Color(0.45, 0.88, 1.0, 1.0)
        outline.width = 3.5
    elif is_hovered:
        fill.color = Color(0.25, 0.70, 1.0, 0.22)
        outline.default_color = Color(0.60, 0.90, 1.0, 1.0)
        outline.width = 3.0
    elif is_reachable:
        fill.color = Color(0.25, 0.75, 0.55, 0.12)
        outline.default_color = Color(0.35, 0.85, 0.65, 0.85)
        outline.width = 2.0
    else:
        fill.color = Color(0.10, 0.35, 0.55, 0.06)
        outline.default_color = Color(0.55, 0.75, 0.85, 0.45)
        outline.width = 1.0
    outline.visible = is_hovered or is_selected or is_current or is_reachable

func _on_mouse_entered() -> void:
    hovered.emit(region_id)

func _on_mouse_exited() -> void:
    unhovered.emit(region_id)

func _on_input_event(_viewport: Node, event: InputEvent,
        _shape_index: int) -> void:
    if event is InputEventMouseButton:
        if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
            clicked.emit(region_id)
```

> **边界命中注意：** 两个区域共享同一条边时，鼠标正好落在边线上可能出现命中优先级差异。首版可通过区域节点 z_index 和 Polygon 轮廓避让处理；若需要完全确定的边界归属，改由 WorldMapScreen 集中使用 Geometry2D.is_point_in_polygon() 做点选，并按 current / selected / z-order 规则裁决。

### 9.3 WorldRegionManager.gd（Autoload）

该脚本负责纯数据和路径逻辑，不直接操纵地图显示节点。建议在 Project Settings → Globals → Autoload 注册为 WorldRegionManager。

```gdscript
extends Node

signal map_loaded

const DEFAULT_MAP_PATH := "res://data/generated/world_map.json"

var world: Dictionary = {}
var regions: Dictionary = {}
var transitions_by_from: Dictionary = {}
var current_region_id: String = ""

func _ready() -> void:
    load_map(DEFAULT_MAP_PATH)

func load_map(path: String = DEFAULT_MAP_PATH) -> bool:
    if not FileAccess.file_exists(path):
        push_error("World map file not found: %s" % path)
        return false
    var file := FileAccess.open(path, FileAccess.READ)
    if file == null:
        push_error("Cannot open world map: %s" % path)
        return false
    var parser := JSON.new()
    var error := parser.parse(file.get_as_text())
    if error != OK:
        push_error("World map JSON error at line %d: %s" % [
            parser.get_error_line(), parser.get_error_message()
        ])
        return false
    if not (parser.data is Dictionary):
        push_error("World map root must be a JSON object")
        return false

    var root: Dictionary = parser.data
    world = root.get("world", {})
    regions.clear()
    transitions_by_from.clear()

    for item in root.get("regions", []):
        if not (item is Dictionary):
            continue
        var id := str(item.get("id", ""))
        if id.is_empty() or regions.has(id):
            push_error("Empty or duplicate region id: %s" % id)
            return false
        regions[id] = item
        transitions_by_from[id] = []

    for item in root.get("transitions", []):
        if not (item is Dictionary):
            continue
        var from_id := str(item.get("from_region", ""))
        var to_id := str(item.get("to_region", ""))
        if not regions.has(from_id) or not regions.has(to_id):
            push_error("Transition references unknown region: %s -> %s" % [from_id, to_id])
            return false
        transitions_by_from[from_id].append(item)

    if current_region_id.is_empty():
        current_region_id = str(world.get("start_region_id", ""))
    map_loaded.emit()
    return true

func get_region(region_id: String) -> Dictionary:
    return regions.get(region_id, {})

func get_neighbors(region_id: String) -> Array[String]:
    var result: Array[String] = []
    for edge in transitions_by_from.get(region_id, []):
        if bool(edge.get("enabled", true)):
            result.append(str(edge.get("to_region", "")))
    return result

func get_transition(from_id: String, to_id: String) -> Dictionary:
    for edge in transitions_by_from.get(from_id, []):
        if str(edge.get("to_region", "")) == to_id and bool(edge.get("enabled", true)):
            return edge
    return {}

func get_transition_for_gate(from_id: String, gate_id: String) -> Dictionary:
    for edge in transitions_by_from.get(from_id, []):
        if str(edge.get("exit_gate_id", "")) == gate_id and bool(edge.get("enabled", true)):
            return edge
    return {}

func can_travel(from_id: String, to_id: String) -> bool:
    return not get_transition(from_id, to_id).is_empty()

func find_path(start_id: String, goal_id: String) -> Array[String]:
    if not regions.has(start_id) or not regions.has(goal_id):
        return []
    if start_id == goal_id:
        return [start_id]

    var distances: Dictionary = {}
    var previous: Dictionary = {}
    var unvisited: Dictionary = {}
    for key in regions.keys():
        var id := str(key)
        distances[id] = INF
        unvisited[id] = true
    distances[start_id] = 0.0

    while not unvisited.is_empty():
        var current := ""
        var best_cost: float = INF
        for key in unvisited.keys():
            var candidate := float(distances.get(key, INF))
            if candidate < best_cost:
                current = str(key)
                best_cost = candidate
        if current.is_empty() or best_cost == INF:
            break
        unvisited.erase(current)
        if current == goal_id:
            break

        for edge in transitions_by_from.get(current, []):
            if not bool(edge.get("enabled", true)):
                continue
            var next_id := str(edge.get("to_region", ""))
            if not unvisited.has(next_id):
                continue
            var edge_cost := maxf(float(edge.get("travel_cost", 1.0)), 0.001)
            var total_cost := best_cost + edge_cost
            if total_cost < float(distances.get(next_id, INF)):
                distances[next_id] = total_cost
                previous[next_id] = current

    if float(distances.get(goal_id, INF)) == INF:
        return []
    var path: Array[String] = [goal_id]
    var cursor := goal_id
    while cursor != start_id:
        if not previous.has(cursor):
            return []
        cursor = str(previous[cursor])
        path.push_front(cursor)
    return path
```

### 9.4 WorldMapScreen.gd

WorldMapScreen 在 _ready 时读取 WorldRegionManager.regions，并为每个区域实例化 RegionVisual。建议主场景只保存视觉状态和 UI 状态；寻路、连接查询留在 WorldRegionManager。

```gdscript
extends Node2D

@export var region_visual_scene: PackedScene
@export var world_map_path := "res://data/generated/world_map.json"

@onready var region_layer: Node2D = $MapContent/RegionLayer
@onready var background: Sprite2D = $MapContent/Background
@onready var route_line: Line2D = $MapContent/RouteLayer/RouteLine

var region_views: Dictionary = {}
var hovered_region_id := ""
var selected_region_id := ""

func _ready() -> void:
    if not WorldRegionManager.load_map(world_map_path):
        return
    var bg_path := str(WorldRegionManager.world.get("background_path", ""))
    if not bg_path.is_empty():
        var texture := load(bg_path) as Texture2D
        if texture != null:
            background.texture = texture

    for id_variant in WorldRegionManager.regions.keys():
        var id := str(id_variant)
        var view := region_visual_scene.instantiate() as RegionVisual
        if view == null:
            push_error("region_visual_scene must instantiate RegionVisual")
            return
        region_layer.add_child(view)
        view.configure(WorldRegionManager.get_region(id))
        view.hovered.connect(_on_region_hovered)
        view.unhovered.connect(_on_region_unhovered)
        view.clicked.connect(_on_region_clicked)
        region_views[id] = view
    _refresh_region_states()

func _on_region_hovered(region_id: String) -> void:
    hovered_region_id = region_id
    _refresh_region_states()

func _on_region_unhovered(region_id: String) -> void:
    if hovered_region_id == region_id:
        hovered_region_id = ""
    _refresh_region_states()

func _on_region_clicked(region_id: String) -> void:
    selected_region_id = region_id
    _draw_route(WorldRegionManager.find_path(
        WorldRegionManager.current_region_id, selected_region_id
    ))
    _refresh_region_states()
    # 在此处更新 RegionInfoPanel，显示区域描述和导航按钮。

func _refresh_region_states() -> void:
    var reachable := WorldRegionManager.get_neighbors(
        WorldRegionManager.current_region_id
    )
    for id_variant in region_views.keys():
        var id := str(id_variant)
        var view = region_views[id]
        view.set_visual_state(
            id == hovered_region_id,
            id == selected_region_id,
            id == WorldRegionManager.current_region_id,
            reachable.has(id)
        )

func _draw_route(path: Array[String]) -> void:
    var points := PackedVector2Array()
    for id in path:
        var region := WorldRegionManager.get_region(id)
        var anchor: Array = region.get("map_anchor", [0.0, 0.0])
        points.append(Vector2(float(anchor[0]), float(anchor[1])))
    route_line.points = points
    route_line.visible = points.size() >= 2
```

注：以上代码是运行时核心骨架。实际项目还需补充 RegionInfoPanel 的数据绑定、Camera2D 缩放/拖动、按键焦点、路线方向箭头、地图卸载清理及错误 UI。若地图节点在多个实例间重复创建，先 queue_free 旧节点再加载新数据。

### 9.5 RegionExitGate.gd 与 RegionSpawnPoint.gd

```gdscript
# RegionExitGate.gd
extends Area2D

@export var gate_id := ""

func _ready() -> void:
    body_entered.connect(_on_body_entered)

func _on_body_entered(body: Node2D) -> void:
    if not body.is_in_group("player_ship"):
        return
    var from_id := WorldRegionManager.current_region_id
    var transition := WorldRegionManager.get_transition_for_gate(from_id, gate_id)
    if transition.is_empty():
        # 没有有效 Transition：保持在当前场景，可播放边界阻挡反馈。
        return
    RegionTravelManager.travel(transition)


# RegionSpawnPoint.gd
extends Marker2D

@export var spawn_id := ""

func _ready() -> void:
    add_to_group("region_spawn_points")
```

### 9.6 RegionTravelManager.gd（Autoload）

```gdscript
extends Node

var pending_spawn_id := ""
var pending_region_id := ""

func travel(transition: Dictionary) -> void:
    var to_id := str(transition.get("to_region", ""))
    var target_region := WorldRegionManager.get_region(to_id)
    var scene_path := str(target_region.get("scene_path", ""))
    if target_region.is_empty() or scene_path.is_empty():
        push_error("Target region or scene_path is missing: %s" % to_id)
        return

    pending_spawn_id = str(transition.get("entry_spawn_id", ""))
    pending_region_id = to_id
    var error := get_tree().change_scene_to_file(scene_path)
    if error != OK:
        pending_spawn_id = ""
        pending_region_id = ""
        push_error("Failed to change region scene: %s" % scene_path)
        return
    WorldRegionManager.current_region_id = to_id

func consume_pending_spawn_id() -> String:
    var value := pending_spawn_id
    pending_spawn_id = ""
    return value
```

目标海域场景加载后，在场景根节点的 _ready 或专用初始化流程中读取 RegionTravelManager.consume_pending_spawn_id()，遍历 region_spawn_points 组，查找 spawn_id 匹配的 Marker2D，将玩家船只 global_position 设置为出生点 global_position。建议先 await get_tree().process_frame，确保节点已进入场景树。

## 10. 游戏场景切换协议

### 10.1 Transition 触发流程

1. 玩家船只进入当前海域的 RegionExitGate。
2. RegionExitGate 读取当前 region_id 和自身 gate_id。
3. WorldRegionManager.get_transition_for_gate() 查找匹配的有向 Transition。
4. 校验 enabled、解锁条件、任务条件及目标 scene_path。
5. RegionTravelManager 缓存 entry_spawn_id 和目标 region_id，调用 change_scene_to_file。
6. 目标海域场景完成初始化，按 entry_spawn_id 定位 Marker2D。
7. 放置玩家船只、恢复航速/朝向等允许继承的状态，并更新 current_region_id。

### 10.2 场景约定

| 约定 | 要求 |
| --- | --- |
| 当前区域 | 每个可玩区域场景启动时必须明确对应 region_id；不得依赖场景文件名推断。 |
| 出口 gate_id | 在单个区域内唯一；必须与对应 Transition.exit_gate_id 完全一致。 |
| 入口 spawn_id | 在目标场景内唯一；必须与进入该场景的 Transition.entry_spawn_id 完全一致。 |
| 玩家船只 | 加入 player_ship 组；场景切换时需要明确哪些状态继承、哪些状态重置。 |
| 加载失败 | 若 scene_path 不存在或切换失败，清空 pending_spawn_id，记录错误并给出玩家反馈。 |

### 10.3 世界地图点击行为

推荐采用两段式交互：单击区域先选中并显示信息；若目标是当前区域的直接邻居，则导航面板显示“航行至该海域”；若目标需要经过多个区域，则显示完整路线和下一目标区域。普通航行模式不允许通过世界地图点击跳过中间海域。若游戏设计有快速旅行功能，应另外定义 fast_travel 权限、费用和解锁规则。

## 11. Agent 地图数据生产接口

### 11.1 设计目标与接入方式

Agent 不应直接操作 Godot 场景节点，也不应在没有校验的情况下覆盖正式地图文件。建议提供本地 Map Pipeline CLI，并可将同一组函数包装成 MCP Server（若所使用的 Agent 支持 MCP）。CLI 是底层稳定接口；MCP 是可选适配层。所有写操作先生成 staging patch，完成校验与差异预览后再 commit。

| 接口组 | 建议工具名 | 功能 |
| --- | --- | --- |
| 读取 | map.inspect | 返回地图摘要、区域 ID、版本、背景尺寸和统计信息。 |
| 读取 | map.get_region | 读取指定区域的 Polygon、属性和场景配置。 |
| 读取 | map.get_neighbors | 读取几何邻接候选与当前已启用 Transition，二者分开返回。 |
| 几何 | map.add_region | 创建区域 Polygon 和属性。 |
| 几何 | map.update_region_polygon | 更新区域边界；要求提供 expected_revision。 |
| 连接 | map.suggest_adjacency | 计算共享边界候选，不自动放行。 |
| 连接 | map.upsert_transition | 创建或更新有向 Transition。 |
| 连接 | map.remove_transition | 删除指定 Transition。 |
| 校验 | map.validate | 检查 ID、Polygon、重叠、场景、出口、连接和孤立区域。 |
| 构建 | map.build | 通过校验后生成 world_map.json。 |
| 查询 | map.find_path | 在指定当前图上返回路径。 |

### 11.2 CLI 参考命令

```bash
# 查看地图摘要
python tools/map_pipeline/cli.py inspect \
  --map data/source/world_regions.tmj \
  --connections data/source/world_connections.json

# 建议几何邻接候选（不自动写入通行关系）
python tools/map_pipeline/cli.py suggest-adjacency \
  --map data/source/world_regions.tmj \
  --min-shared-boundary 8

# 校验地图
python tools/map_pipeline/cli.py validate \
  --map data/source/world_regions.tmj \
  --connections data/source/world_connections.json

# 构建运行时 JSON
python tools/map_pipeline/cli.py build \
  --map data/source/world_regions.tmj \
  --connections data/source/world_connections.json \
  --out res://data/generated/world_map.json

# 查询路径
python tools/map_pipeline/cli.py find-path \
  --from sea_001 --to sea_017 \
  --connections data/source/world_connections.json
```

### 11.3 Agent 工具参数示例

```json
{
  "tool": "map.add_region",
  "expected_revision": "sha256:9d6f...",
  "region": {
    "id": "sea_north_01",
    "display_name": "Northwind Sea",
    "region_type": "ocean",
    "polygon": [[820, 120], [1140, 150], [1200, 410], [900, 470]],
    "map_anchor": [1010, 290],
    "properties": {
      "danger_level": 3
    }
  },
  "reason": "Add a northern sea region requested by world design"
}
```

### 11.4 Agent 返回结果统一格式

```json
{
  "ok": true,
  "operation_id": "op_20261121_00017",
  "revision": "sha256:af21...",
  "changed_files": [
    "data/source/world_regions.tmj"
  ],
  "validation": {
    "errors": [],
    "warnings": [
      "sea_north_01 is geometrically adjacent to sea_004 but has no transition"
    ]
  },
  "summary": "Region added to staging workspace; commit is available after review."
}
```

### 11.5 Agent 操作安全规则

- 所有写操作必须提供 expected_revision（源文件哈希或 revision）；不匹配时拒绝写入，防止覆盖用户在 Tiled 中的新编辑。
- Agent 修改源文件前先复制到 staging 工作区；默认不直接覆盖正式 .tmj / connections.json。
- map.validate 未通过时禁止 map.build；错误与警告分级返回。
- 添加 Transition 时必须明确 from_region、to_region、exit_gate_id、entry_spawn_id；不能仅根据区域几何自动补齐。
- 删除区域前必须检查其入边、出边、场景引用、存档引用和任务引用。
- 地图构建输出应记录 source_revision、schema_version、build_time 和工具版本，便于复现。

### 11.6 推荐的 Agent 工作流

```text
用户自然语言需求
       │
       ▼
Agent 调用 map.inspect / map.get_region
       │
       ▼
生成变更计划（区域几何 + 属性 + Transition）
       │
       ▼
调用 map.add_region / map.update_region_polygon / map.upsert_transition
       │
       ▼
map.validate（错误必须清零）
       │
       ▼
向用户展示变更摘要和邻接差异
       │
       ▼
用户确认或自动化策略批准 commit
       │
       ▼
map.build → world_map.json → Godot 预览场景
```

## 12. 地图构建校验规则

| 检查项 | 错误（阻止构建） | 警告（允许构建但需确认） |
| --- | --- | --- |
| 区域 ID | 为空、重复、格式非法 | ID 命名不符合推荐风格。 |
| Polygon 点集 | 少于 3 个点、重复退化、面积为 0、自相交 | 顶点数量异常多，建议简化。 |
| 地图范围 | 坐标超出 world.width / height | 区域贴近边缘。 |
| 区域重叠 | 不同区域发生超过容差的面积重叠 | 共享边界差异小于容差但不完全一致。 |
| 区域缝隙 | 仅在配置要求“覆盖区域”时检查关键空洞 | 未分配区域的空白海域。 |
| Transition | from/to 区域不存在、自环、重复边、travel_cost <= 0 | 几何上不相邻但存在 Transition（需说明 portal / canal 等原因）。 |
| 场景引用 | scene_path 不存在或为空（对标记为可玩的区域） | 场景暂未制作但区域可作为未开放区域。 |
| 出口和入口 | gate_id 或 spawn_id 在场景中找不到 | 目标区域没有反向 Transition。 |
| 可达性 | 起始区域无法到达配置要求的关键区域 | 某些区域图上孤立，可能是设计意图。 |

几何校验建议在 Pipeline 阶段执行，而不是每次游戏启动都执行。游戏启动时只做轻量结构校验，发现错误时记录可读日志并回退到安全状态。

## 13. 性能、资源与存档

### 13.1 性能基线

- 约 100 个 Polygon2D + Area2D 作为世界地图 UI 的初始实现规模通常足够轻量；先以实际设备 profile 为准，不提前引入复杂空间索引。
- 地图静态几何只在加载时创建一次；hover 时只更新相关区域状态，避免每帧遍历并重建全部 Polygon 顶点。
- Dijkstra 对 100 节点规模足够；路线查询可在点击区域时执行，不必每帧计算。
- 背景大图根据目标平台准备合适分辨率与压缩格式；避免把超大原图无条件常驻显存。

### 13.2 存档字段

```json
{
  "world_state": {
    "current_region_id": "sea_001",
    "discovered_region_ids": ["sea_001", "sea_002"],
    "selected_route": ["sea_001", "sea_002", "sea_017"]
  }
}
```

存档中只保存区域 ID 和游戏进度，不保存 Polygon 坐标。地图几何以资源文件为准；若未来正式发布后修改区域 ID，应提供迁移映射表，避免旧存档失效。

## 14. 测试方案与验收标准

| 测试阶段 | 测试内容 | 验收标准 |
| --- | --- | --- |
| MVP-1 区域显示 | 5 个 Polygon、背景图对齐、缩放和平移 | 所有区域边界与背景图片保持像素级对齐。 |
| MVP-2 鼠标交互 | 悬停、离开、点击、当前区域状态 | 悬停高亮正确；离开后 current 状态保留；点击 ID 正确。 |
| MVP-3 Graph | 直接邻接、单向边、双向边、Dijkstra | 路径严格遵循已启用 Transition；不可达时返回空路径。 |
| MVP-4 场景切换 | A 出口进入 B、B 出口返回 A、错误 gate 和 spawn | 玩家进入正确出生点；非法连接不得切换。 |
| MVP-5 规模测试 | 约 100 个区域加载、悬停、寻路 | 无明显输入延迟；路线更新不导致卡顿。 |
| MVP-6 Agent 流程 | Agent 新增区域、建议邻接、更新连接、校验和构建 | 没有未经校验的改动进入运行时 JSON；构建结果可复现。 |

### 14.1 必须覆盖的边界用例

- 鼠标正好落在两个 Polygon 的共享边界；
- 两个区域只在一个顶点接触；
- 区域 Polygon 为凹多边形；
- 当前区域和目标区域相同；
- 目标区域存在，但没有任何可用路径；
- Transition 已启用，但 gate_id 或 entry_spawn_id 拼写错误；
- 场景加载失败或目标场景没有玩家船只；
- Agent 修改期间人类同时更新了 Tiled 文件，revision 冲突必须被检测。

## 15. 分阶段实施计划

| 阶段 | 实施内容 | 交付物 |
| --- | --- | --- |
| 阶段 0：资源规范 | 测量背景图片尺寸，确定坐标原点、地图范围和区域命名规则。 | world_map_spec.md、资源目录。 |
| 阶段 1：交互原型 | Tiled 绘制 5 个区域；Godot 显示 Polygon，完成 hover / click。 | WorldMapScreen.tscn、RegionVisual.tscn。 |
| 阶段 2：数据和邻接 | 完成 TMJ 转换器、Transition JSON、校验器和 Dijkstra。 | map_pipeline、world_map.json、WorldRegionManager.gd。 |
| 阶段 3：游戏切换 | 配置 A/B 两个海域场景、ExitGate 和 SpawnPoint。 | RegionTravelManager.gd、场景切换 Demo。 |
| 阶段 4：扩展至 100 区域 | 完善美术状态、路线展示、100 区域数据和性能测试。 | 完整世界地图。 |
| 阶段 5：Agent 自动生产 | 提供 CLI / MCP 工具、staging、revision、validate、build。 | Agent Tool API、变更审计日志。 |

## 16. 风险与设计决策记录

| 风险 / 决策 | 处理方式 |
| --- | --- |
| 区域几何相邻但不可通行 | Graph 独立保存；几何算法只产生候选邻接。 |
| 背景图更新造成区域漂移 | 固定地图尺寸和坐标约定；背景更换必须触发坐标校验和版本更新。 |
| Tiled / Godot 插件版本变化 | 运行时不依赖 YATI；插件锁版本并在升级时做导入回归。 |
| 多边形边界精度差 | 构建时设置容差并输出共享边界诊断；不自动修改玩家可见边界。 |
| 跨区场景切换状态丢失 | RegionTravelManager 暂存出生点 ID；另行定义船速、航向、任务状态等继承白名单。 |
| Agent 覆盖人工编辑 | revision/哈希检查 + staging + diff + commit。 |
| 区域数量增长 | 首版 100 区域不引入过度优化；超过数百或复杂多边形再考虑空间索引和分区加载。 |

## 17. 项目目录建议

```text
res://
├── addons/
│   └── yati/                       # 可选；不作为运行时硬依赖
├── art/
│   └── world_map/
│       ├── world_ocean.png         # 现有背景图
│       ├── ocean_overlay.png      # 可选装饰层
│       └── region_icons/           # 港口/标记图标
├── data/
│   ├── source/
│   │   ├── world_regions.tmj      # Tiled 编辑源
│   │   └── world_connections.json # 有向通行边
│   └── generated/
│       └── world_map.json         # Godot 运行时数据
├── scenes/
│   ├── world_map/
│   │   ├── WorldMapScreen.tscn
│   │   └── RegionVisual.tscn
│   └── regions/
│       ├── sea_001.tscn
│       └── sea_002.tscn
├── scripts/
│   ├── world_map/
│   │   ├── WorldMapScreen.gd
│   │   ├── RegionVisual.gd
│   │   └── WorldRegionManager.gd
│   └── travel/
│       ├── RegionTravelManager.gd
│       ├── RegionExitGate.gd
│       └── RegionSpawnPoint.gd
└── tools/
    └── map_pipeline/
        ├── cli.py
        ├── tiled_reader.py
        ├── geometry.py
        ├── validator.py
        └── builder.py
```

## 18. 外部资料与兼容性说明

本设计使用以下官方或项目资料核对工具能力。外部插件会持续更新，正式集成前应以项目锁定版本的 README、发行说明和本机导入测试为准。

- Godot 4.6 Area2D 文档：Area2D 通过 CollisionShape2D / CollisionPolygon2D 定义空间区域，并提供区域相关信号。https://docs.godotengine.org/en/4.6/classes/class_area2d.html
- Godot 4.6 CollisionPolygon2D 文档：支持凹 / 凸多边形，作为 CollisionObject2D 的碰撞形状。https://docs.godotengine.org/en/4.6/classes/class_collisionpolygon2d.html
- Tiled JSON Map Format：支持 JSON 导出、Polygon Object 顶点数组及对象自定义属性。https://doc.mapeditor.org/en/latest/reference/json-map-format/
- YATI GitHub：Tiled TMX / TMJ 导入 Godot 4；README 说明 2.2.7 需要 Godot 4.3+，并标注在 Godot 4.6.1 + Tiled 1.12 测试。https://github.com/Kiamo2/YATI
- Godot 4.6 Release：官方版本说明。https://godotengine.org/releases/4.6/

> **版本提醒：** 本设计针对用户指定的 Godot 4.6 编写。若实际安装版本为 4.6.x 的不同补丁版，建议先用 5 个区域完成 YATI（若启用）、CollisionPolygon2D、change_scene_to_file 和资源导出测试，再固定依赖版本。

## 附录 A：首版配置建议

| 配置项 | 建议初值 | 说明 |
| --- | --- | --- |
| region_count | 约 100 | 首版目标规模。 |
| min_polygon_vertices | 3 | 低于 3 个点视为无效。 |
| max_polygon_vertices | 按实际地图控制 | 建议避免过度密集顶点；可做轮廓简化。 |
| min_shared_boundary_px | 8 px（初始值） | 几何邻接候选的最小共享边长，应根据背景图尺寸调整。 |
| geometry_tolerance_px | 0.5～1 px | 用于边界共线 / 重叠判定；不是实际可通行阈值。 |
| travel_cost | 1.0 | 默认每跨一个海域成本；可按距离、危险度调整。 |
| map_camera_zoom | 按窗口与底图尺寸设置 | 限制最小/最大缩放；鼠标滚轮以鼠标位置为缩放中心可作为增强项。 |

## 附录 B：首个可运行原型验收清单

- 导入一张实际世界地图背景图片；记录原始宽高。
- 在 Tiled 中绘制 5 个不规则 Polygon 区域，并设置唯一 region_id。
- 导出 TMJ，运行 Map Pipeline 生成 world_map.json。
- Godot 加载背景和 5 个区域；缩放、平移时区域仍与底图对齐。
- 鼠标悬停时区域边缘高亮；离开后恢复；当前区域保持独立高亮。
- 单击区域可显示名称和 ID；路线按有向 Transition 生成。
- 在 Sea_A 中触发 east_gate，确认仅在存在 A→B Transition 时切换到 Sea_B。
- Sea_B 使用 west_spawn 放置玩家船只；错误 spawn_id 时给出清晰日志。
- Agent 新增一个区域后，必须通过 validate 才能 build；revision 冲突时不能覆盖。
