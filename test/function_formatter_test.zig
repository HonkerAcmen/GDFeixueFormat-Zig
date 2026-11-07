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
