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
        std.debug.print("用法: GDFeixueFormat <目录>\n", .{});
        return error.InvalidArguments;
    };
    if (args.next() != null) {
        std.debug.print("只接受一个目标目录。\n", .{});
        return error.InvalidArguments;
    }

    // 目录句柄由当前入口统一释放，格式化模块只借用它遍历和读写文件。
    const root = try openTargetDirectory(init.io, path);
    defer root.close(init.io);
    const result = try directory_formatter.formatDirectory(init.io, init.gpa, root);
    std.debug.print("已格式化 {d} 个 GDScript 文件。", .{result.changed_files});
    if (result.failed_files > 0) {
        std.debug.print("\n{d} 个文件处理失败。\n", .{result.failed_files});
        return error.FormatFailed;
    }
    std.debug.print("\n", .{});
}
