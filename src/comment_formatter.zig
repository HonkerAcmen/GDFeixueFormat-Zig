const std = @import("std");
const Allocator = std.mem.Allocator;

pub const MAX_LINE_TABS: usize = 20;
const TAB_WIDTH: usize = 4;

/// 将文本追加到正在构造的注释行中。
fn appendText(output: *std.ArrayList(u8), allocator: Allocator, text: []const u8) Allocator.Error!void {
    try output.appendSlice(allocator, text);
}

/// 返回 UTF-8 字符在终端和常见代码编辑器中的近似显示宽度。
fn characterWidth(codepoint: u21) usize {
    if (codepoint == '\t') return TAB_WIDTH;
    if (codepoint >= 0x1100 and (codepoint <= 0x115f or codepoint == 0x2329 or codepoint == 0x232a)) return 2;
    if ((codepoint >= 0x2e80 and codepoint <= 0xa4cf) or
        (codepoint >= 0xac00 and codepoint <= 0xd7a3) or
        (codepoint >= 0xf900 and codepoint <= 0xfaff) or
        (codepoint >= 0xfe10 and codepoint <= 0xfe6f) or
        (codepoint >= 0xff01 and codepoint <= 0xff60) or
        (codepoint >= 0xffe0 and codepoint <= 0xffe6) or
        (codepoint >= 0x1f300 and codepoint <= 0x1faff) or
        (codepoint >= 0x20000 and codepoint <= 0x3fffd)) return 2;
    return 1;
}

/// 读取文本中的下一个 UTF-8 字符，并返回字符字节数与显示宽度。
fn nextCharacter(text: []const u8, index: usize) struct { byte_count: usize, width: usize } {
    const byte_count = std.unicode.utf8ByteSequenceLength(text[index]) catch 1;
    if (index + byte_count > text.len) return .{ .byte_count = 1, .width = 1 };
    const codepoint = std.unicode.utf8Decode(text[index .. index + byte_count]) catch text[index];
    return .{ .byte_count = byte_count, .width = characterWidth(codepoint) };
}

/// 计算注释文本的显示列数，用于决定是否需要折行。
fn displayWidth(text: []const u8) usize {
    var width: usize = 0;
    var index: usize = 0;
    while (index < text.len) {
        const character = nextCharacter(text, index);
        width += character.width;
        index += character.byte_count;
    }
    return width;
}

/// 将原注释行转成 `##` 文档行，并在最大列宽处按字符边界折行。
pub fn formatDocumentation(
    allocator: Allocator,
    source_lines: []const []const u8,
    indentation: []const u8,
) ![][]const u8 {
    var formatted_lines: std.ArrayList([]const u8) = .empty;
    const indentation_width = displayWidth(indentation);
    const prefix_width = indentation_width + 3;
    const max_width = MAX_LINE_TABS * TAB_WIDTH;
    const content_width = if (prefix_width < max_width) max_width - prefix_width else 1;

    for (source_lines) |source_line| {
        const trimmed_line = std.mem.trimStart(u8, source_line, " \t");
        if (trimmed_line.len == 0) {
            try appendEmptyDocumentationLine(allocator, &formatted_lines, indentation);
            continue;
        }
        if (trimmed_line[0] != '#') return error.InvalidDocumentationLine;

        var content_start: usize = 1;
        if (content_start < trimmed_line.len and trimmed_line[content_start] == '#') content_start += 1;
        const content = std.mem.trim(u8, trimmed_line[content_start..], " \t");
        try appendWrappedDocumentation(allocator, &formatted_lines, indentation, content, content_width);
    }
    return try formatted_lines.toOwnedSlice(allocator);
}

/// 为注释段落逐字符折行，中文宽字符和制表符按显示列数计算。
fn appendWrappedDocumentation(
    allocator: Allocator,
    output_lines: *std.ArrayList([]const u8),
    indentation: []const u8,
    content: []const u8,
    max_content_width: usize,
) !void {
    if (content.len == 0) {
        try appendEmptyDocumentationLine(allocator, output_lines, indentation);
        return;
    }

    var line: std.ArrayList(u8) = .empty;
    defer line.deinit(allocator);
    var content_width: usize = 0;
    var index: usize = 0;
    var previous_was_space = false;
    while (index < content.len) {
        const character = nextCharacter(content, index);
        const bytes = content[index .. index + character.byte_count];
        index += character.byte_count;
        if (bytes.len == 1 and (bytes[0] == ' ' or bytes[0] == '\t')) {
            previous_was_space = true;
            continue;
        }

        const separator_width: usize = if (previous_was_space and content_width > 0) 1 else 0;
        if (content_width > 0 and content_width + separator_width + character.width > max_content_width) {
            try appendDocumentationLine(allocator, output_lines, indentation, line.items);
            line.clearRetainingCapacity();
            content_width = 0;
        } else if (separator_width > 0) {
            try line.append(allocator, ' ');
            content_width += 1;
        }
        previous_was_space = false;

        if (content_width > 0 and content_width + character.width > max_content_width) {
            try appendDocumentationLine(allocator, output_lines, indentation, line.items);
            line.clearRetainingCapacity();
            content_width = 0;
        }
        try line.appendSlice(allocator, bytes);
        content_width += character.width;
    }
    if (line.items.len > 0) try appendDocumentationLine(allocator, output_lines, indentation, line.items);
}

/// 生成一行缩进与 `##` 前缀规范化的文档注释。
fn appendDocumentationLine(
    allocator: Allocator,
    output_lines: *std.ArrayList([]const u8),
    indentation: []const u8,
    content: []const u8,
) !void {
    const line = if (content.len == 0)
        try std.fmt.allocPrint(allocator, "{s}##", .{indentation})
    else
        try std.fmt.allocPrint(allocator, "{s}## {s}", .{ indentation, content });
    try output_lines.append(allocator, line);
}

/// 保留文档段落之间的空行，并规范为空的 `##` 文档行。
fn appendEmptyDocumentationLine(
    allocator: Allocator,
    output_lines: *std.ArrayList([]const u8),
    indentation: []const u8,
) !void {
    try output_lines.append(allocator, try std.fmt.allocPrint(allocator, "{s}##", .{indentation}));
}
