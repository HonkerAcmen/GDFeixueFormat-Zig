const std = @import("std");
const Allocator = std.mem.Allocator;
const formatter = @import("formatter");

/// 汇总目录处理结果，供命令行显示成功数并决定退出状态。
pub const Result = struct {
    changed_files: usize = 0,
    failed_files: usize = 0,
};

/// 递归格式化目录中扩展名为 `.gd` 的普通文件。
pub fn formatDirectory(io: std.Io, allocator: Allocator, root: std.Io.Dir) !Result {
    var result: Result = .{};
    var walker = try root.walk(allocator);
    defer walker.deinit();
    while (try walker.next(io)) |entry| {
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
    }
    return result;
}
