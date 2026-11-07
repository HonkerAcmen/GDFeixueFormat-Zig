const std = @import("std");

/// 汇总 GDScript 总行数、有效代码行、独立注释行和空行。
pub const Statistics = struct {
    total_lines: usize = 0,
    code_lines: usize = 0,
    comment_lines: usize = 0,
    blank_lines: usize = 0,

    /// 将另一个脚本的行数统计累加到当前结果中。
    pub fn add(self: *Statistics, other: Statistics) void {
        self.total_lines += other.total_lines;
        self.code_lines += other.code_lines;
        self.comment_lines += other.comment_lines;
        self.blank_lines += other.blank_lines;
    }
};

/// 统计格式化后文本的物理行数，并按代码、注释和空行分类。
pub fn count(text: []const u8) Statistics {
    var result: Statistics = .{};
    if (text.len == 0) return result;

    const line_ending_count = std.mem.countScalar(u8, text, '\n');
    const has_final_line_ending = text[text.len - 1] == '\n';
    result.total_lines = line_ending_count + @intFromBool(!has_final_line_ending);

    var lines = std.mem.splitScalar(u8, text, '\n');
    var line_index: usize = 0;
    while (line_index < result.total_lines) : (line_index += 1) {
        const line = lines.next() orelse break;
        const trimmed = std.mem.trim(u8, line, " \t\r");
        if (trimmed.len == 0) {
            result.blank_lines += 1;
        } else if (std.mem.startsWith(u8, trimmed, "#")) {
            result.comment_lines += 1;
        } else {
            result.code_lines += 1;
        }
    }
    return result;
}
