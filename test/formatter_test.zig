const std = @import("std");
const formatter = @import("formatter");

// 用例：确认连续函数间始终保留两个空行。
test "相邻函数之间保留两个空行" {
    const actual = try formatter.formatText(std.testing.allocator, "func first():\n\tpass\nfunc second():\n\tpass\n");
    defer std.testing.allocator.free(actual);
    try std.testing.expectEqualStrings("func first():\n\tpass\n\n\nfunc second():\n\tpass\n", actual);
}

// 用例：确认行尾空格、CRLF 和空格缩进都按统一规则处理。
test "清理行尾空格、统一 CRLF 并转换空格缩进" {
    const actual = try formatter.formatText(std.testing.allocator, "var value = 1  \r\n    var next = 2\r\n");
    defer std.testing.allocator.free(actual);
    try std.testing.expectEqualStrings("var value = 1\n\tvar next = 2\n", actual);
}

// 用例：确认字符串内部的伪代码不会触发函数间距或缩进规则。
test "三引号字符串内容保持原样" {
    const source = "var text = \"\"\"\nfunc fake(a: int):\n\n  keep spacing\n\"\"\"\nfunc real():\n\tpass\n";
    const actual = try formatter.formatText(std.testing.allocator, source);
    defer std.testing.allocator.free(actual);
    try std.testing.expectEqualStrings("var text = \"\"\"\nfunc fake(a: int):\n\n  keep spacing\n\"\"\"\n\n\nfunc real():\n\tpass\n", actual);
}

// 用例：同一文件重复格式化时，第二次结果不再变化。
test "格式化结果可以重复运行而不再变化" {
    const once = try formatter.formatText(std.testing.allocator, "extends Node\nclass_name Example\nfunc run(a: int, b: int, c: int, d: int):\n\tpass\n");
    defer std.testing.allocator.free(once);
    const twice = try formatter.formatText(std.testing.allocator, once);
    defer std.testing.allocator.free(twice);
    try std.testing.expectEqualStrings(once, twice);
}
