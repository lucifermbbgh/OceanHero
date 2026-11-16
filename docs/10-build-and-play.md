# 构建导出与游玩说明

| 项 | 内容 |
|---|---|
| 引擎 | Godot 4.7.2-stable |
| 导出模板 | 4.7.2.stable（已安装到 `~/Library/Application Support/Godot/export_templates/4.7.2.stable`） |
| 产物目录 | `export/`（已加入 .gitignore，不入库） |

## 一、产物清单

| 文件 | 平台 | 大小 | 说明 |
|---|---|---|---|
| `export/碧海英豪.app` | macOS | 164 MB | 可直接双击运行的应用包 |
| `export/SeaHeroes-macOS.zip` | macOS | 59 MB | 分发用压缩包（解压得到 .app） |
| `export/SeaHeroes-Windows.exe` | Windows | 106 MB | 单文件可执行（pck 已内嵌，无需附带文件） |

- macOS 包为 **universal 二进制**（arm64 + x86_64），Apple Silicon 与 Intel 通用。
- Windows 包为 **x86_64 PE32+ GUI 程序**。
- 两个包都**不需要安装、不需要注册、不需要联网**。

## 二、重新导出

```bash
# macOS
godot --headless --path projects/SeaHeroes --export-release "macOS" export/SeaHeroes-macOS.zip

# Windows
godot --headless --path projects/SeaHeroes --export-release "Windows" export/SeaHeroes-Windows.exe
```

或在编辑器里：项目 → 导出 → 选择预设 → 导出项目。

### 导出前的三个前提

| 前提 | 说明 |
|---|---|
| 导出模板已安装 | 缺失时导出会直接失败 |
| `rendering/textures/vram_compression/import_etc2_astc=true` | macOS universal/arm64 导出强制要求，否则报错 |
| `data/manifest.txt` 是最新的 | 见下方「数据清单」 |

### 数据清单（重要）

导出后的 `res://` **无法通过目录扫描发现文件**，所以 `DataRegistry` 改为读 `data/manifest.txt`。
新增/删除 `.tres` 数据后必须重新生成：

```bash
cd projects/SeaHeroes
find data -name "*.tres" | sed 's|^|res://|' | sort > data/manifest.txt
```

导出预设里已配置 `include_filter="*.txt"`，保证清单被打进包内。
若忘记更新，游戏仍会启动，但会**加载不到新数据**（表现为数量对不上）。

## 三、在 macOS 上游玩

1. 打开 `projects/SeaHeroes/export/`
2. 双击 `碧海英豪.app`

**首次打开可能提示「无法验证开发者」**（未签名）：
- 方法一：右键点图标 → **打开** → 再点「打开」
- 方法二：终端执行 `xattr -dr com.apple.quarantine 碧海英豪.app`

> 这两个包是在本机生成的，文件本身不带 quarantine 属性，通常双击即可打开。

## 四、在 Windows 上游玩

1. 把 `SeaHeroes-Windows.exe` 拷贝到 Windows 机器（U 盘 / 网盘均可）
2. **双击运行**

**首次运行可能被 SmartScreen 拦截**（未签名）：
点「**更多信息**」→「**仍要运行**」。

- 无需安装运行库（引擎静态编译）
- 无需安装 DirectX / .NET
- 单个 exe 即可运行，不要单独移动或删除它

## 五、常见问题

| 现象 | 原因 | 处理 |
|---|---|---|
| 双击 macOS 应用提示「已损坏」 | 从网上下载后被加 quarantine | `xattr -dr com.apple.quarantine 碧海英豪.app` |
| Windows 提示「Windows 已保护你的电脑」 | 未做代码签名 | 更多信息 → 仍要运行 |
| 打开后是黑屏/空白 | 显卡驱动或渲染后端问题 | 项目使用 GL Compatibility，兼容性较好；可尝试更新驱动 |
| 游戏内没有声音 | 本版未接音频 | 非故障 |

## 六、存档位置

| 平台 | 路径 |
|---|---|
| macOS | `~/Library/Application Support/Godot/app_userdata/碧海英豪/` |
| Windows | `%APPDATA%\Godot\app_userdata\碧海英豪\` |

存档与编辑器运行时的存档位置相同（同一 `config/name`），
所以**在编辑器里玩的存档，导出包可以直接读到**，反之亦然。
