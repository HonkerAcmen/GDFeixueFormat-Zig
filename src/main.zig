const std = @import("std");
const directory_formatter = @import("directory_formatter");

/// 根据绝对或相对路径打开可递归遍历的目标目录。
fn openTargetDirectory(io: std.Io, path: []const u8) !std.Io.Dir {
    if (std.fs.path.isAbsolute(path)) {
        return std.Io.Dir.openDirAbsolute(io, path, .{ .iterate = true });
    }
    return std.Io.Dir.cwd().openDir(io, path, .{ .iterate = true });
}

/// 读取命令行目录参数，调用格式化流程并报告处理结果。
pub fn main(init: std.process.Init) !void {
    var args = std.process.Args.Iterator.init(init.minimal.args);
    _ = args.next();
    const path = args.next() orelse {
        std.debug.print("用法: GDFeixueFormat <目录> [-g <文件或文件夹> ...]\n", .{});
        return error.InvalidArguments;
    };
    var ignored: std.ArrayList([]const u8) = .empty;
    defer ignored.deinit(init.gpa);
    var ignoring = false;
    while (args.next()) |argument| {
        if (std.mem.eql(u8, argument, "-g")) {
            if (ignoring and ignored.items.len == 0) return error.InvalidArguments;
            ignoring = true;
        } else if (!ignoring or argument.len == 0 or argument[0] == '-') {
            std.debug.print("用法: GDFeixueFormat <目录> [-g <文件或文件夹> ...]\n", .{});
            return error.InvalidArguments;
        } else {
            try ignored.append(init.gpa, argument);
        }
    }
    if (ignoring and ignored.items.len == 0) {
        std.debug.print("-g 后至少需要一个忽略路径。\n", .{});
        return error.InvalidArguments;
    }

    // 目录句柄由当前入口统一释放，格式化模块只借用它遍历和读写文件。
    const root = try openTargetDirectory(init.io, path);
    defer root.close(init.io);
    const result = try directory_formatter.formatDirectoryIgnoring(init.io, init.gpa, root, ignored.items);
    std.debug.print("已处理 {d} 个 GDScript 文件，格式化修改 {d} 个。\n", .{ result.processed_files, result.changed_files });
    std.debug.print(
        "代码行数：总计 {d} 行（代码 {d} 行，注释 {d} 行，空行 {d} 行）。\n",
        .{ result.lines.total_lines, result.lines.code_lines, result.lines.comment_lines, result.lines.blank_lines },
    );
    if (result.failed_files > 0) {
        std.debug.print("\n{d} 个文件处理失败。\n", .{result.failed_files});
        return error.FormatFailed;
    }
    std.debug.print("\n", .{});
}
