const std = @import("std");
const formatter = @import("formatter");

// 用例：普通参数达到四个时逐个换行。
test "四个及以上参数逐个换行" {
    const actual = try formatter.formatText(std.testing.allocator, "func run(a: int, b: int, c: int, d: int):\n\tpass\n");
    defer std.testing.allocator.free(actual);
    try std.testing.expectEqualStrings("func run(\n\ta: int,\n\tb: int,\n\tc: int,\n\td: int\n):\n\tpass\n", actual);
}

// 用例：三个普通参数不触发参数换行阈值。
test "三个普通参数保持原行" {
    const source = "func run(a: int, b: int, c: int):\n\tpass\n";
    const actual = try formatter.formatText(std.testing.allocator, source);
    defer std.testing.allocator.free(actual);
    try std.testing.expectEqualStrings(source, actual);
}

// 用例：Callable 参数不受参数数量阈值限制，始终展开。
test "Callable 参数无论数量都换行" {
    const actual = try formatter.formatText(std.testing.allocator, "func run(callback: Callable):\n\tpass\n");
    defer std.testing.allocator.free(actual);
    try std.testing.expectEqualStrings("func run(\n\tcallback: Callable\n):\n\tpass\n", actual);
}

// 用例：匿名回调参数换行后，内部参数再增加一层缩进。
test "匿名回调的参数再缩进一层" {
    const actual = try formatter.formatText(std.testing.allocator, "func run(callback: Callable = func(a: int, b: int): pass):\n\tpass\n");
    defer std.testing.allocator.free(actual);
    try std.testing.expectEqualStrings("func run(\n\tcallback: Callable = func(\n\t\ta: int,\n\t\tb: int\n\t): pass\n):\n\tpass\n", actual);
}

// 用例：字符串中的逗号不能被当作参数分隔符。
test "字符串内部逗号不拆分参数" {
    const actual = try formatter.formatText(std.testing.allocator, "func run(a: String = \"x,y\", b: int, c: int, d: int):\n\tpass\n");
    defer std.testing.allocator.free(actual);
    try std.testing.expectEqualStrings("func run(\n\ta: String = \"x,y\",\n\tb: int,\n\tc: int,\n\td: int\n):\n\tpass\n", actual);
}

// 用例：已有多行签名去掉尾随逗号，并保持返回类型和函数体边界。
test "多行函数签名移除尾随逗号并统一格式" {
    const actual = try formatter.formatText(std.testing.allocator, "func run(\n\ta: int,\n\tb: int,\n\tc: int,\n) -> void:\n\tpass\n");
    defer std.testing.allocator.free(actual);
    try std.testing.expectEqualStrings("func run(\n\ta: int,\n\tb: int,\n\tc: int\n) -> void:\n\tpass\n", actual);
}

// 用例：函数上方的单井号注释提升为文档并紧邻函数声明。
test "单井号注释转换为函数文档" {
    const actual = try formatter.formatText(std.testing.allocator, "# 执行攻击\nfunc attack():\n\tpass\n");
    defer std.testing.allocator.free(actual);
    try std.testing.expectEqualStrings("## 执行攻击\nfunc attack():\n\tpass\n", actual);
}

// 用例：文档块前保留函数间距，文档行之间和函数名之间不插入普通空行。
test "多行函数文档保持连续并统一井号" {
    const source = "class_name Enemy\n# 第一行说明\n\n## 第二行说明\nfunc attack():\n\tpass\n";
    const actual = try formatter.formatText(std.testing.allocator, source);
    defer std.testing.allocator.free(actual);
    try std.testing.expectEqualStrings("class_name Enemy\n\n\n## 第一行说明\n##\n## 第二行说明\nfunc attack():\n\tpass\n", actual);
}

// 用例：超过二十个 Tab 宽度的文档会折行，续行也带 `##` 前缀。
test "超长函数文档按二十个 Tab 宽度折行" {
    var content: [90]u8 = undefined;
    @memset(&content, 'a');
    const source = try std.fmt.allocPrint(std.testing.allocator, "# {s}\nfunc run():\n\tpass\n", .{content});
    defer std.testing.allocator.free(source);
    const actual = try formatter.formatText(std.testing.allocator, source);
    defer std.testing.allocator.free(actual);
    const expected = try std.fmt.allocPrint(
        std.testing.allocator,
        "## {s}\n## {s}\nfunc run():\n\tpass\n",
        .{ content[0..77], content[77..] },
    );
    defer std.testing.allocator.free(expected);
    try std.testing.expectEqualStrings(expected, actual);
}

// 用例：中文宽字符按两个显示列折行，输出行宽不超过二十个 Tab。
test "中文函数文档按显示宽度折行" {
    const source = "# 这是一个用于验证中文注释宽度折行规则的非常长的函数文档内容这是一个用于验证中文注释宽度折行规则的非常长的函数文档内容这是一个用于验证中文注释宽度折行规则的非常长的函数文档内容\nfunc run():\n\tpass\n";
    const actual = try formatter.formatText(std.testing.allocator, source);
    defer std.testing.allocator.free(actual);
    try std.testing.expectEqualStrings(
        "## 这是一个用于验证中文注释宽度折行规则的非常长的函数文档内容这是一个用于验证中\n" ++
            "## 文注释宽度折行规则的非常长的函数文档内容这是一个用于验证中文注释宽度折行规则\n" ++
            "## 的非常长的函数文档内容\nfunc run():\n\tpass\n",
        actual,
    );
}
