const std = @import("std");
const formatter = @import("directory_formatter");

// 用例：验证递归处理、扩展名筛选、格式化结果和无关文件保护。
test "递归格式化 GDScript 并跳过其他扩展名" {
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    try temporary.dir.createDir(std.testing.io, "nested", .default_dir);
    const nested = try temporary.dir.openDir(std.testing.io, "nested", .{});
    defer nested.close(std.testing.io);
    try nested.writeFile(std.testing.io, .{
        .sub_path = "sample.gd",
        .data = "extends Node\nclass_name Sample\nfunc run():\n\tpass\nfunc next():\n\tpass\n",
    });
    try temporary.dir.writeFile(std.testing.io, .{ .sub_path = "readme.txt", .data = "keep\n" });

    // 临时目录隔离文件系统副作用，避免用例写入真实游戏项目。
    const result = try formatter.formatDirectory(std.testing.io, std.testing.allocator, temporary.dir);
    try std.testing.expectEqual(@as(usize, 1), result.processed_files);
    try std.testing.expectEqual(@as(usize, 1), result.changed_files);
    try std.testing.expectEqual(@as(usize, 0), result.failed_files);
    try std.testing.expectEqual(@as(usize, 9), result.lines.total_lines);
    try std.testing.expectEqual(@as(usize, 5), result.lines.code_lines);
    try std.testing.expectEqual(@as(usize, 0), result.lines.comment_lines);
    try std.testing.expectEqual(@as(usize, 4), result.lines.blank_lines);
    const formatted = try nested.readFileAlloc(std.testing.io, "sample.gd", std.testing.allocator, .unlimited);
    defer std.testing.allocator.free(formatted);
    try std.testing.expectEqualStrings("class_name Sample extends Node\n\n\nfunc run():\n\tpass\n\n\nfunc next():\n\tpass\n", formatted);
    const unchanged = try temporary.dir.readFileAlloc(std.testing.io, "readme.txt", std.testing.allocator, .unlimited);
    defer std.testing.allocator.free(unchanged);
    try std.testing.expectEqualStrings("keep\n", unchanged);
}
