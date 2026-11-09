const std = @import("std");
const Allocator = std.mem.Allocator;
const formatter = @import("formatter");
const line_statistics = @import("line_statistics");

/// 汇总目录处理结果，供命令行显示成功数并决定退出状态。
pub const Result = struct {
    processed_files: usize = 0,
    changed_files: usize = 0,
    failed_files: usize = 0,
    lines: line_statistics.Statistics = .{},
};

/// 递归格式化目录中扩展名为 `.gd` 的普通文件。
pub fn formatDirectory(io: std.Io, allocator: Allocator, root: std.Io.Dir) !Result {
    return formatDirectoryIgnoring(io, allocator, root, &.{});
}

/// 忽略路径相对于目标目录解析；目录匹配包含所有子项，不使用通配符。
pub fn formatDirectoryIgnoring(io: std.Io, allocator: Allocator, root: std.Io.Dir, ignored_paths: []const []const u8) !Result {
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const scratch = arena.allocator();
    const root_path = try root.realPathFileAlloc(io, ".", scratch);
    var ignored: std.ArrayList([]const u8) = .empty;
    for (ignored_paths) |path| {
        if (path.len == 0) return error.InvalidArguments;
        try ignored.append(scratch, try std.fs.path.resolve(scratch, &.{ root_path, path }));
    }
    var result: Result = .{};
    var walker = try root.walkSelectively(allocator);
    defer walker.deinit();
    while (try walker.next(io)) |entry| {
        const absolute = try std.fs.path.resolve(allocator, &.{ root_path, entry.path });
        defer allocator.free(absolute);
        var skip = false;
        for (ignored.items) |path| {
            if (std.mem.eql(u8, absolute, path) or
                (std.mem.startsWith(u8, absolute, path) and
                    (std.mem.endsWith(u8, path, std.fs.path.sep_str) or absolute[path.len] == std.fs.path.sep)))
            {
                skip = true;
                break;
            }
        }
        if (skip) continue;
        if (entry.kind == .directory) {
            try walker.enter(io, entry);
            continue;
        }
        if (entry.kind != .file or !std.mem.endsWith(u8, entry.basename, ".gd")) continue;
        // 单个文件失败时继续处理其余脚本，最终把失败总数交给 CLI 报告。
        const source_text = entry.dir.readFileAlloc(io, entry.basename, allocator, .unlimited) catch {
            result.failed_files += 1;
            continue;
        };
        defer allocator.free(source_text);
        const formatted = formatter.formatText(allocator, source_text) catch {
            result.failed_files += 1;
            continue;
        };
        defer allocator.free(formatted);
        if (!std.mem.eql(u8, source_text, formatted)) {
            entry.dir.writeFile(io, .{ .sub_path = entry.basename, .data = formatted }) catch {
                result.failed_files += 1;
                continue;
            };
            result.changed_files += 1;
        }
        result.processed_files += 1;
        result.lines.add(line_statistics.count(formatted));
    }
    return result;
}
