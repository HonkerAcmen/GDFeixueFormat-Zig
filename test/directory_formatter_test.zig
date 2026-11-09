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

// 忽略目录时不进入，路径比较必须按组件匹配，不能误伤名称前缀相同的目录。
test "忽略多个文件和目录且保留同名前缀路径" {
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    for ([_][]const u8{ "skip", "skip_more", "keep" }) |name| {
        try temporary.dir.createDir(std.testing.io, name, .default_dir);
    }
    const source = "var value = 1  \n";
    const paths = [_][]const u8{ "skip/a.gd", "skip_more/a.gd", "keep/a.gd", "keep/b.gd", "root.gd" };
    for (paths) |path| try temporary.dir.writeFile(std.testing.io, .{ .sub_path = path, .data = source });
    const absolute = try temporary.dir.realPathFileAlloc(std.testing.io, "root.gd", std.testing.allocator);
    defer std.testing.allocator.free(absolute);
    const result = try formatter.formatDirectoryIgnoring(std.testing.io, std.testing.allocator, temporary.dir, &.{ "./skip/", "keep/../keep/a.gd", absolute, "missing.gd" });
    try std.testing.expectEqual(@as(usize, 2), result.processed_files);
    try std.testing.expectEqual(@as(usize, 2), result.changed_files);
    try std.testing.expectEqual(@as(usize, 0), result.failed_files);
    try std.testing.expectEqual(@as(usize, 2), result.lines.total_lines);
    for (paths, 0..) |path, index| {
        const actual = try temporary.dir.readFileAlloc(std.testing.io, path, std.testing.allocator, .unlimited);
        defer std.testing.allocator.free(actual);
        try std.testing.expectEqualStrings(if (index == 1 or index == 3) "var value = 1\n" else source, actual);
    }
}

test "忽略目标目录本身时不处理文件" {
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    try temporary.dir.writeFile(std.testing.io, .{ .sub_path = "a.gd", .data = "var a = 1  \n" });
    const result = try formatter.formatDirectoryIgnoring(std.testing.io, std.testing.allocator, temporary.dir, &.{"."});
    try std.testing.expectEqual(@as(usize, 0), result.processed_files);
}
