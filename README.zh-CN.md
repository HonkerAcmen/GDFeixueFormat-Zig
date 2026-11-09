# GDFeixueFormat

[English](README.md) | **简体中文**

GDFeixueFormat 是使用 Zig 编写的 GDScript 命令行格式化工具。它会递归扫描目标目录，格式化扩展名为 `.gd` 的普通文件，并将变化写回原文件。它不依赖 Godot 编辑器或运行时。

## 项目结构

```text
build.zig
src/
  main.zig                   命令行参数与程序入口
  directory_formatter.zig    目录遍历和文件读写
  formatter.zig              文本格式化流程与空白规则
  declaration_formatter.zig  class_name / extends 规范化
  function_formatter.zig     函数参数与回调格式化
  comment_formatter.zig     函数文档注释规范化与折行
  line_statistics.zig       格式化后 GDScript 行数统计
  gdscript_ast.zig          分词器与语句、容器 AST
  gdscript_syntax.zig        括号匹配和参数解析
test/
  all.zig                     全量测试入口
  fixtures/                   集成用例的输入和预期输出文件
  declaration_formatter_test.zig
  directory_formatter_test.zig
  formatter_test.zig
  function_formatter_test.zig
  line_statistics_test.zig
  gdscript_ast_test.zig
  gdscript_syntax_test.zig
  TEST_CASES.md              完整测试用例清单
```

文本格式化核心不负责文件读写，目录模块不解析 GDScript 语法，命令行入口也不包含格式规则。`gdscript_ast.zig` 负责分词并构建语句节点和嵌套容器节点，格式化器根据节点类型决定缩进和空行。函数文档处理和行数统计仍由独立模块负责。测试集中放在 `test/`，按模块职责组织。`test/fixtures/` 保存较长回调样例的输入与预期输出。[`test/TEST_CASES.md`](test/TEST_CASES.md) 列出每个具名用例及其目的（50 个行为用例和 1 个聚合测试入口）。

## 环境要求

- Zig **0.17.1**。本项目尚未验证其他版本。
- 支持运行 Zig 的终端环境。本项目目前已在 macOS 上构建和测试；Linux、Windows 原生构建尚未验证。
- 对需要格式化的 Godot 项目文件具有读写权限。

检查 Zig 版本：

```sh
zig version
```

预期输出为 `0.17.1`。如果终端找不到 `zig`，请安装 Zig、将其加入 `PATH`，然后重新打开终端。

## 从源码编译

在 GDFeixueFormat 项目根目录运行：

```sh
zig build
```

编译成功后，程序位于：

```text
zig-out/bin/GDFeixueFormat
```

Windows 下程序名带 `.exe` 后缀。

需要优化构建时可以运行：

```sh
zig build -Doptimize=ReleaseFast
```

开发和调试通常使用默认构建即可。`zig-out/` 与 `.zig-cache/` 是生成目录，不应提交到版本控制。

## 运行格式化器

### 直接运行编译结果

```sh
./zig-out/bin/GDFeixueFormat /path/to/godot/project
```

参数是要格式化的目录，可以使用绝对路径，也可以使用相对于当前工作目录的路径。例如，终端已位于 Godot 项目根目录时：

```sh
/path/to/GDFeixueFormat/zig-out/bin/GDFeixueFormat .
```

### 通过 Zig 构建步骤运行

```sh
zig build run -- /path/to/godot/project
```

`--` 后的参数会传给格式化器。要格式化相对于当前工作目录的目录，可以运行：

```sh
zig build run -- .
```

该命令从 GDFeixueFormat 项目目录启动，因此 `.` 指的是格式化器项目本身。格式化其他项目时，请传入 Godot 项目路径。

### 忽略文件和文件夹

```sh
./zig-out/bin/GDFeixueFormat /path/to/godot/project -g addons scripts/generated.gd "folder with spaces"
zig build run -- /path/to/godot/project -g addons scripts/generated.gd
```

`-g` 后可跟多个路径。相对路径以目标目录为基准，也支持绝对路径；忽略文件夹会跳过其全部子目录。路径按完整组件匹配，不支持通配符，不存在的路径不影响运行。被忽略的文件不会修改，也不计入文件数和行数统计。带空格的路径需要加引号；`-g` 后必须至少提供一个路径。

### 运行行为

- 递归处理目标目录内的 `.gd` 普通文件。
- 跳过其他扩展名的文件。
- 只写回内容发生变化的文件。
- 会直接修改文件。首次运行前请提交或备份当前工作。
- 当前没有预览或 dry-run 模式。运行后请使用 `git diff` 检查变化。
- 输出已处理和有修改的 GDScript 文件数，并汇总成功处理文件的行数：总行数、代码行、独立注释行和空行。
- 统计格式化后的文本，即使文件内容未变化也会计入。末尾换行不额外算作一行；行尾注释计入代码行。
- 目标目录无法打开或文件读写失败时，程序会以非零状态退出。

## 运行测试与格式检查

在项目根目录运行全部 Zig 测试：

```sh
zig build test --summary all
```

当前测试套件共 51 项并全部通过：50 个具名行为用例和 1 个聚合模块注册测试。覆盖词法分析、语句与容器 AST 构建、嵌套父子关系、无效分隔符、注解与续行、链式调用、回调分支与调用闭合处续行符、声明和函数格式化、文档折行、声明间距、行数统计、幂等性及递归文件筛选。所有用例见[完整测试清单](test/TEST_CASES.md)。

检查 Zig 源码格式：

```sh
zig fmt --check build.zig src test
```

提交源码前建议依次运行：

```sh
zig fmt --check build.zig src test
zig build test --summary all
zig build
```

## 格式规则

- 相邻的 `class_name Example` 和 `extends Node` 合并为 `class_name Example extends Node`，输入顺序不限。
- 只有 `class_name` 而没有 `extends` 时，保留单独的 `class_name`，不会自动补充父类。
- 函数之间保留两个空行。
- 枚举声明正上方的章节注释或文档注释与 `enum` 紧贴，中间不插入空行。
- 普通函数有四个或更多参数时逐个换行。
- `Callable` 和匿名回调参数无论数量多少都会换行；匿名回调内部参数再缩进一层。
- 函数上方直接相邻的独立 `#` 或 `##` 注释会视为函数文档。所有文档行统一为 `##`，文档块紧贴函数；块内空行规范为 `##`。
- 函数文档最大显示宽度为 20 个 Tab 停靠位（80 列，Tab 按 4 列计算）。缩进和 `##` 前缀也计入宽度；常见中日韩宽字符按 2 列计算。折行后的每一行都以 `##` 开头。
- 语句节点区分函数、变量、常量、信号、枚举、注解、控制流和表达式。Godot 4 的 `class_name`、`trait` 等关键字会被识别为关键字，而不是用户自定义标识符。
- 以 `:` 开始的缩进代码块、字典字面量和枚举成员体拥有不同的 AST 类型。嵌套数组与字典表示为带类型的容器节点，字典花括号不会被当作代码块缩进作用域。
- 注解块保持附着于对应声明；即使多行注解之间有空行，也会在格式化时移除这类间隔。反斜杠续行会作为同一个表达式处理，续行增加两级缩进。
- 多行调用中的匿名回调会跟踪函数体和嵌套 `if` 分支：仅在回调代码块或最后一条语句需要继续参数表达式时添加行尾 `\\`；查找调用闭合的 `)` 或 `),` 时跳过空行；以 `return`、`continue` 或 `break` 结束的 `if` 分支会移除多余续行符。
- 以点开头的链式方法调用会与前一表达式归为一组，并使用两级续行缩进。
- 函数边界保留两个空行；信号与枚举声明组之间保留一个空行；枚举前的注释和注解都紧贴各自对应的声明。
- 括号、方括号或花括号不匹配或未闭合时，格式化器会保留该文件原文，不执行部分重排。
- 清理行尾空格，将 CRLF 转换为 LF，并将纯空格缩进转换为 Tab。
- 多行字符串的内容保持原样。

### 函数文档与行数统计的实现原理

文本格式化器处理到函数声明时，会检查此前已收集的行。如果函数前面有独立注释块，就先将注释块从原位置取出，规范化并折行，再放到函数头正上方。函数间距规则先处理注释块前的空行，因此函数与文档之间不会插入空行，而文档前仍保留规范要求的间距。这样在统一函数间距时，注释仍会跟随对应函数。

文档格式化器会移除行首的 `#` 或 `##`，清理两侧水平空白，再统一输出 `##` 前缀。注释块内部的空行转换为 `##`。折行时按 UTF-8 字符而非字节遍历，并估算常见中日韩宽字符的显示宽度；遇到空格时优先在词边界换行，连续长文本则在字符边界换行，保证不超过 80 列。

GDScript 解析器先把标识符、关键字、注解、字符串、注释、运算符、分隔符和显式续行符分词。字符串与注释作为单个词法单元处理，因此其中的括号字符不会影响语法结构。随后解析器按语句构造节点，记录源码行范围、缩进父节点、代码块边界和续行信息；第二遍匹配嵌套分隔符，为圆括号、数组、字典和枚举成员体建立带类型的容器节点，并保留容器之间的父子关系。花括号的含义由声明与表达式上下文决定，不会被一律解释为代码块。这是面向当前格式规则的轻量 AST，并非完整的 Godot 语言语义 AST。

格式化器按源码顺序遍历这些语句节点。处理多行容器时，它会计算当前行仍处于哪些父容器中：数组、字典和枚举成员体增加一级缩进，圆括号表达式续行增加两级；闭合行回到外层节点的缩进。显式 `\\` 续行和以点开头的链式调用也会留在所属表达式中，并使用两级续行缩进。在多行匿名回调中，格式化器还会跟踪回调函数体和嵌套 `if` 分支，区分正常继续与由 `return`、`continue` 或 `break` 结束的分支，并据此保留或清除续行符；它会跳过空行查找外层调用的闭合符。枚举声明间距规则也会识别前置注释，确保注释直接跟随对应枚举。这些选择遵循 [Godot GDScript 风格指南](https://docs.godotengine.org/en/latest/tutorials/scripting/gdscript/gdscript_styleguide.html)中关于容器与表达式续行的排版建议。解析器同时记录注解所属的声明，因此可以清理注解块内部的空行，而不拆开注解和声明的关系。

每个 `.gd` 文件成功格式化后，目录格式化器会统计格式化后的内容并累计到目录结果中。仅包含空白的行计为空行；第一个非空白字符为 `#` 的行计为注释行；其他行计为代码行，所以行尾注释仍属于代码行。命令行最后输出统计结果。统计格式化后的内容，可以直接反映工具运行完成后脚本的行数。

输入示例：

```gdscript
extends Node2D
class_name Example

func attack(a: int, b: int, c: int, d: int) -> void:
	pass
```

格式化结果：

```gdscript
class_name Example extends Node2D


func attack(
	a: int,
	b: int,
	c: int,
	d: int
) -> void:
	pass
```

## 接入 Godot 项目

### 方式一：从独立目录调用

适合先试用或本机使用，无需修改 Godot 项目文件。

1. 在 GDFeixueFormat 源码目录编译一次：

   ```sh
   cd /path/to/GDFeixueFormat
   zig build
   ```

2. 将 Godot 项目目录作为参数传入：

   ```sh
   /path/to/GDFeixueFormat/zig-out/bin/GDFeixueFormat /path/to/godot/project
   ```

3. 在 Godot 项目仓库检查变更：

   ```sh
   cd /path/to/godot/project
   git diff -- '*.gd'
   ```

每台开发机都需要安装兼容版本的 Zig 并本地编译，或者获取与本机操作系统和处理器架构匹配的程序。

### 方式二：将源码纳入 Godot 项目仓库

团队共享时，可以将格式化器源码作为 Git 子模块加入，或直接纳入仓库的专用目录，例如 `tools/GDFeixueFormat/`：

```sh
git submodule add <GDFeixueFormat-repository-url> tools/GDFeixueFormat
git submodule update --init --recursive
```

请将 `<GDFeixueFormat-repository-url>` 替换为实际使用的仓库地址。

然后从 Godot 项目根目录编译和运行：

```sh
cd tools/GDFeixueFormat
zig build test --summary all
zig build
cd ../..
tools/GDFeixueFormat/zig-out/bin/GDFeixueFormat .
```

如果源码放在其他目录，请相应调整可执行文件路径。不要在项目配置中写入开发者机器上的绝对路径。

### 接入项目脚本或 CI

源码纳入仓库后，可将下列步骤加入项目的任务运行器、编辑器工具、提交前检查或 CI：

1. 在运行环境安装受支持的 Zig 版本。
2. 在 GDFeixueFormat 目录运行 `zig build test --summary all`。
3. 在该目录运行 `zig build`。
4. 使用 Godot 项目根目录作为参数运行编译出的程序。
5. 决定流程是保留格式化结果，还是发现格式差异后拒绝通过。

若 CI 要检查格式而不保留修改，可以运行格式化器后检查跟踪的 GDScript 文件是否变化：

```sh
tools/GDFeixueFormat/zig-out/bin/GDFeixueFormat .
git diff --exit-code -- '*.gd'
```

`git diff` 返回非零表示格式化器修改了文件。当前工具直接写回文件，没有只检查模式。

## 常见问题

### `zig: command not found`

终端无法通过 `PATH` 找到 Zig。请安装 Zig 0.17.1、将它加入 `PATH`，并使用 `zig version` 确认。

### 找不到 `zig-out/bin/GDFeixueFormat`

编译尚未成功完成。请在 GDFeixueFormat 项目根目录运行 `zig build` 后再启动程序。

### 格式化器报告文件错误

确认目标目录存在，并且当前用户可以读写其中的 `.gd` 文件。单个文件失败不会阻止工具继续处理其他脚本；处理结束后，程序会以非零状态退出。

### 一次修改了很多文件

格式化器会直接改写不符合规则的 `.gd` 文件。请使用 `git diff -- '*.gd'` 检查结果。若发现意外变化，请恢复对应文件，并添加回归测试后再调整格式化规则。
