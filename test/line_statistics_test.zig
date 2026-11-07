const std = @import("std");
const statistics = @import("line_statistics");

// 用例：统计脚本行数并区分代码、独立注释和空行。
test "代码注释与空行分别统计" {
    const result = statistics.count("extends Node\n## 文档\n\n\t# 注释\n\tpass\n");
    try std.testing.expectEqual(@as(usize, 5), result.total_lines);
    try std.testing.expectEqual(@as(usize, 2), result.code_lines);
    try std.testing.expectEqual(@as(usize, 2), result.comment_lines);
    try std.testing.expectEqual(@as(usize, 1), result.blank_lines);
}

// 用例：末尾换行不额外产生一行，空文本没有物理行。
test "末尾换行与空文本行数正确" {
    try std.testing.expectEqual(@as(usize, 0), statistics.count("").total_lines);
    try std.testing.expectEqual(@as(usize, 1), statistics.count("pass\n").total_lines);
    try std.testing.expectEqual(@as(usize, 2), statistics.count("pass\n\n").total_lines);
}
