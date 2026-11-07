# Test case inventory

Run the full suite from the project root:

```sh
zig build test --summary all
```

The suite contains 50 named behavior cases and one aggregate import test (`test/all.zig`). The aggregate test ensures every test module is registered with Zig's test runner.

## `declaration_formatter_test.zig`

1. **反序 class_name / extends 声明合并并保持 class_name 在前** — Merges declarations written in reverse order into the normalized single-line header.
2. **正序 class_name / extends 声明合并为一行** — Keeps an already ordered class declaration on one line.
3. **没有 extends 时保留单独的 class_name** — Does not invent an `extends` clause when none exists.
4. **多行字符串里的声明原样保留** — Does not rewrite declaration-like text inside multiline strings.

## `function_formatter_test.zig`

1. **四个及以上参数逐个换行** — Wraps each argument when a function has four or more parameters.
2. **三个普通参数保持原行** — Leaves a short ordinary signature on one line.
3. **Callable 参数无论数量都换行** — Wraps signatures containing callback parameters regardless of parameter count.
4. **匿名回调的参数再缩进一层** — Indents anonymous callback arguments one level deeper.
5. **字符串内部逗号不拆分参数** — Ignores commas inside strings while splitting arguments.
6. **多行函数签名移除尾随逗号并统一格式** — Normalizes multiline signatures and removes a trailing comma.
7. **单井号注释转换为函数文档** — Converts a single-hash comment above a function into documentation form.
8. **多行函数文档保持连续并统一井号** — Keeps consecutive documentation lines together and normalizes their prefixes.
9. **超长函数文档按二十个 Tab 宽度折行** — Wraps long documentation at the configured width.
10. **中文函数文档按显示宽度折行** — Uses display width when wrapping Chinese documentation.

## `formatter_test.zig`

1. **相邻函数之间保留两个空行** — Enforces the blank-line boundary between adjacent functions.
2. **清理行尾空格、统一 CRLF 并转换空格缩进** — Normalizes line endings, trailing whitespace, and indentation.
3. **三引号字符串内容保持原样** — Preserves multiline string contents.
4. **格式化结果可以重复运行而不再变化** — Checks formatter idempotence.
5. **嵌套字典与数组按容器层级缩进** — Indents nested dictionary and array literals by container depth.
6. **注解附着声明且信号枚举与函数分组** — Keeps annotations with declarations and applies declaration-group spacing.
7. **函数注解块保持紧贴函数声明** — Keeps function annotations adjacent to their function.
8. **无效括号结构保留原文本** — Avoids rewriting text when delimiter syntax is invalid.
9. **函数体与后续类级变量之间有两个空行** — Separates a function body from the following class-level variable.
10. **函数体空行后回到类级作用域** — Restores class-level indentation after a blank line in a function body.
11. **括号内嵌套容器按 AST 父子层级缩进** — Uses AST container parentage for nested indentation.
12. **反斜杠续行和链式调用增加两级缩进** — Indents explicit continuations and chained calls.
13. **多行注解参数与变量声明保持相邻** — Keeps a multiline annotation attached to its variable declaration.
14. **同一行注解与变量之间不插入空行** — Avoids inserting a blank line between inline annotation and variable.
15. **多行调用结束后的链式调用保持归属与缩进** — Keeps a chain attached to its preceding multiline call and indents it consistently.
16. **信号枚举与变量组的空行规则稳定** — Applies stable spacing between signals, enums, and variable groups.
17. **枚举前的标题注释和文档注释不留空行** — Keeps heading and documentation comments adjacent to enum declarations.
18. **混合 AST 排版结果可以重复运行** — Checks idempotence across combined AST formatting rules.
19. **控制流代码块首条语句紧贴冒号** — Keeps the first statement attached to its control-flow header.
20. **匿名回调代码块续行符位置正确** — Places continuation markers on callback suite headers and before a call close, including when blank lines intervene.
21. **匿名回调的 return 分支不增加冒号续行符** — Removes a redundant continuation marker from a callback `if` branch that returns.
22. **完整右键菜单回调缩进结构正确** — Preserves nested callback, branch, and return indentation in a full fixture.

## `gdscript_ast_test.zig`

1. **Godot 4 声明关键字分类** — Classifies supported Godot 4 declaration keywords.
2. **字典与枚举花括号分别解析** — Distinguishes dictionary braces from enum declaration braces.
3. **注解与反斜杠续行进入语句 AST** — Records annotations and explicit line continuations in statement nodes.
4. **分隔符词法识别忽略字符串与注释内容** — Does not treat delimiter characters inside strings or comments as syntax.
5. **缩进代码块与字典容器保持不同的 AST 作用域** — Distinguishes indentation-based suites from dictionary literal containers.
6. **嵌套容器 AST 保留父节点关系** — Preserves parent relationships among nested containers.
7. **注解声明与静态函数前缀正确分类** — Classifies annotation declarations, static functions, and declaration prefixes.
8. **未闭合与错误配对括号标记为无效** — Detects unclosed and mismatched delimiters.
9. **链式调用记录在所属表达式节点中** — Associates a leading-dot chained call with its expression node.

## `gdscript_syntax_test.zig`

1. **嵌套结构与字符串里的逗号不会拆分参数** — Splits arguments without confusing nested or quoted commas.
2. **签名闭合定位会跳过字符串中的右括号** — Finds the signature boundary while ignoring closing parentheses inside strings.

## `line_statistics_test.zig`

1. **代码注释与空行分别统计** — Counts code, comments, and blank lines separately.
2. **末尾换行与空文本行数正确** — Handles trailing newlines and empty input correctly.

## `directory_formatter_test.zig`

1. **递归格式化 GDScript 并跳过其他扩展名** — Recursively formats GDScript files while skipping unrelated extensions.
