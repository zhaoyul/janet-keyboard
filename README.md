# scada 软键盘

一个用 **Janet + Win32 原生 FFI** 实现的轻量级屏幕软键盘。无需 .NET，单文件可执行，支持拖拽缩放、Shift 切换大小写、长按 Shift 切换输入法中/英模式。

---

## 功能特性

- 数字键 `0-9`
- QWERTY 字母键 `a-z`
- `Shift` 键：短按切换大小写，长按切换输入法中/英
- 右下角输入法按钮：点击切换输入法中/英
- `Space`、`Backspace`、`Enter`
- 右下角拖动柄，可按固定宽高比缩放整个键盘
- 点击按键不抢夺目标窗口焦点
- 窗口标题固定为 `SCADA`
- 支持通过启动参数设置输入法按钮文案语言

---

如图：
![键盘](imgs/keyboard.png)

## 项目结构

```
scada-keyboard/
├── softkeyboard.janet    # 软键盘源代码（Janet + Win32 FFI）
├── project.janet         # jpm 项目配置
├── build-exe.bat         # Windows 编译脚本
├── build/                # jpm 构建输出目录
│   └── scada-keyboard.exe
├── scada-keyboard.exe    # 最终可执行文件（从 build/ 复制出来）
└── README.md             # 本文件
```

---

## 环境要求

- Windows 10/11 x64
- [Janet](https://janet-lang.org/)（已安装并加入 PATH）
- [jpm](https://github.com/janet-lang/jpm)（通常随 Janet 一起安装）
- Visual Studio 2022（需要 C++ 桌面开发工作负载，用于链接生成 exe）

---

## 快速运行

如果你已经拿到了 `scada-keyboard.exe`，直接双击运行即可。键盘窗口会置顶显示，打开记事本等输入窗口后点击按键即可输入。

也可以传入语言 code，设置右下角输入法按钮的显示文字：

```batch
scada-keyboard.exe --code=en_gb
```

不传参数或传入未支持的 code 时，默认使用中文 `zh_cn`。

### 支持的语言 code

| code | 语言 | 输入法按钮文案 |
| --- | --- | --- |
| `zh_cn` | 中文 | 输入法 |
| `en_gb` | 英文 | Input Method |
| `ja_jp` | 日文 | 入力方式 |
| `ar_eg` | 阿拉伯语 | طريقة الإدخال |
| `az_az` | 阿塞拜疆语 | Daxiletmə üsulu |
| `bn_bd` | 孟加拉语 | ইনপুট পদ্ধতি |
| `ru_ru` | 俄罗斯语 | Метод ввода |
| `ca_es` | 加泰罗尼亚语 | Mètode d'entrada |
| `cs_cz` | 捷克语 | Metoda vstupu |
| `da_dk` | 丹麦语 | Inputmetode |
| `de_de` | 德语 | Eingabemethode |
| `el_gr` | 希腊语 | Μέθοδος εισόδου |
| `es_es` | 西班牙语 | Método de entrada |
| `eu_es` | 巴斯克语 | Sarrera metodoa |

---

## 源码运行

在项目目录下：

```bash
janet softkeyboard.janet
```

这会直接启动软键盘窗口。

源码运行也支持相同的语言 code：

```bash
janet softkeyboard.janet --code=ja_jp
```

---

## 编译成 exe

由于 Windows 下 MSVC 的 `cl.exe` 不在默认 PATH 中，需要先初始化 Visual Studio 编译环境。项目已提供 `build-exe.bat`：

```batch
cd scada-keyboard
build-exe.bat
```

编译完成后，可执行文件会生成在：

- `build/scada-keyboard.exe`
- 同时复制一份到 `scada-keyboard.exe`

### 手动编译

如果你已经打开了 **x64 Native Tools Command Prompt for VS 2022**，可以执行：

```batch
cd scada-keyboard
jpm --headerpath="C:\Users\a123\scoop\apps\janet\current\C" --libpath="C:\Users\a123\scoop\apps\janet\current\C" --is-msvc build
```

> 注意：根据你的 Janet 安装路径，可能需要调整 `headerpath` 和 `libpath`。它们应指向包含 `janet.h` 和 `libjanet.lib` 的目录。

---

## 使用说明

1. 启动 `scada-keyboard.exe`
2. 点击目标输入窗口（如记事本、浏览器输入框），使其获得焦点
3. 点击软键盘上的按键输入字符
4. 短按 `Shift` 切换大小写
5. 点击右下角输入法按钮切换输入法中/英模式
6. 长按 `Shift`（约 0.4 秒）也可以切换输入法中/英模式
7. 拖动右下角 `◢` 缩放键盘
8. 点击窗口右上角 `×` 关闭

---

## 实现要点

- **不自定义 WNDPROC**：Janet 的 `ffi/trampoline` 只支持单一签名回调，无法直接作为 Windows 窗口过程使用。因此采用系统内置 `STATIC` 控件做按键，主窗口使用 `DefWindowProcW`，通过轮询鼠标状态检测点击。
- **不抢焦点**：主窗口和子控件都设置 `WS_EX_NOACTIVATE`，发送按键前不再切换焦点。
- **字体随缩放**：根据按键高度动态创建 GDI 字体，并通过 `WM_SETFONT` 设置给每个控件。

---

## 已知限制

- 仅支持 Windows x64
- 不包含完整的标点符号层
- 输入法按钮和长按 Shift 的中/英切换都依赖于当前输入法把 `Shift` 作为中/英切换键

---

## 许可证

MIT
