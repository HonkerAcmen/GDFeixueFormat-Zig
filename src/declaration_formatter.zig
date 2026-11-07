const std = @import("std");
const Allocator = std.mem.Allocator;

// 本模块只处理文件头声明，不负责函数签名或普通代码空白。
/// 将相邻的 class_name / extends 声明收敛为 `class_name Name extends Base`。
pub fn formatDeclarations(allocator: Allocator, lines: *std.ArrayList([]const u8)) !void {
    var index: usize = 0;
    var multiline_quote: u8 = 0;
    while (index + 1 < lines.items.len) {
        const first = std.mem.trim(u8, lines.items[index], " \t");
        const second = std.mem.trim(u8, lines.items[index + 1], " \t");
        if (multiline_quote != 0) {
            // 字符串里的文本不是 GDScript 声明，必须跳过合并检查。
            const marker: [3]u8 = .{ multiline_quote, multiline_quote, multiline_quote };
            if (std.mem.indexOf(u8, first, &marker) != null) multiline_quote = 0;
            index += 1;
            continue;
        }
        if (std.mem.count(u8, first, "\"\"\"") == 1) {
            multiline_quote = '"';
            index += 1;
            continue;
        }
        if (std.mem.count(u8, first, "'''") == 1) {
            multiline_quote = '\'';
            index += 1;
            continue;
        }

        const class_first = std.mem.startsWith(u8, first, "class_name ") and std.mem.indexOfScalar(u8, first, '#') == null;
        const extends_first = std.mem.startsWith(u8, first, "extends ") and std.mem.indexOfScalar(u8, first, '#') == null;
        const class_second = std.mem.startsWith(u8, second, "class_name ") and std.mem.indexOfScalar(u8, second, '#') == null;
        const extends_second = std.mem.startsWith(u8, second, "extends ") and std.mem.indexOfScalar(u8, second, '#') == null;
        if ((class_first and extends_second) or (extends_first and class_second)) {
            const class_line = if (class_first) first else second;
            const extends_line = if (extends_first) first else second;
            lines.items[index] = try std.fmt.allocPrint(allocator, "{s} {s}", .{ class_line, extends_line });
            _ = lines.orderedRemove(index + 1);
            continue;
        }
        index += 1;
    }
}
