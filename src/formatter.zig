const std = @import("std");
const Allocator = std.mem.Allocator;
const syntax = @import("gdscript_syntax");
const declarations = @import("declaration_formatter");
const functions = @import("function_formatter");
const comments = @import("comment_formatter");

// 本模块负责文本处理顺序；语法判断和文件读写分别交给专属模块。
/// 将文本片段追加到输出缓冲区。
fn appendText(list: *std.ArrayList(u8), allocator: Allocator, value: []const u8) Allocator.Error!void {
    try list.appendSlice(allocator, value);
}

/// 函数声明前清理多余空行，并统一保留两个空行。
fn appendFunctionSpacing(allocator: Allocator, lines: *std.ArrayList([]const u8)) !void {
    while (lines.items.len > 0 and std.mem.trim(u8, lines.items[lines.items.len - 1], " \t").len == 0) {
        _ = lines.pop();
    }
    if (lines.items.len > 0) {
        try lines.append(allocator, "");
        try lines.append(allocator, "");
    }
}

/// 判断去除行首缩进后，文本是否为空。
fn isBlankLine(line: []const u8) bool {
    return std.mem.trim(u8, line, " \t").len == 0;
}

/// 判断一行是否为独立的 GDScript 注释，而不是代码行尾注释。
fn isCommentLine(line: []const u8) bool {
    return std.mem.startsWith(u8, std.mem.trimStart(u8, line, " \t"), "#");
}

/// 找到紧邻函数的注释块，忽略块与函数之间原有的空行。
fn findFunctionDocumentation(lines: []const []const u8) ?struct { start: usize, end: usize } {
    var end = lines.len;
    while (end > 0 and isBlankLine(lines[end - 1])) end -= 1;
    if (end == 0 or !isCommentLine(lines[end - 1])) return null;

    var start = end;
    while (start > 0) {
        const previous_line = lines[start - 1];
        if (isCommentLine(previous_line) or isBlankLine(previous_line)) {
            start -= 1;
        } else {
            break;
        }
    }
    while (start < end and isBlankLine(lines[start])) start += 1;
    return .{ .start = start, .end = end };
}

/// 将函数文档从缓冲区取出并格式化，避免函数间距规则把文档与函数分开。
fn takeFunctionDocumentation(
    allocator: Allocator,
    source_line: []const u8,
    output_lines: *std.ArrayList([]const u8),
) !?[][]const u8 {
    const block = findFunctionDocumentation(output_lines.items) orelse return null;
    const indentation_length = source_line.len - std.mem.trimStart(u8, source_line, " \t").len;
    const indentation = source_line[0..indentation_length];
    const formatted = try comments.formatDocumentation(allocator, output_lines.items[block.start..block.end], indentation);

    while (output_lines.items.len > block.start) _ = output_lines.pop();
    return formatted;
}

/// 将以空格缩进的代码行转换为 Tab 缩进，多行字符串由调用方绕过此函数。
fn normalizeIndentation(allocator: Allocator, line: []const u8) ![]const u8 {
    const leading_len = line.len - std.mem.trimStart(u8, line, " \t").len;
    const leading = line[0..leading_len];
    if (leading_len == 0 or std.mem.indexOfScalar(u8, leading, '\t') != null) return line;

    var converted: std.ArrayList(u8) = .empty;
    defer converted.deinit(allocator);
    const tabs = leading_len / 4;
    const spaces = leading_len % 4;
    for (0..tabs) |_| try converted.append(allocator, '\t');
    for (0..spaces) |_| try converted.append(allocator, ' ');
    try appendText(&converted, allocator, line[leading_len..]);
    return try converted.toOwnedSlice(allocator);
}

/// 收集并格式化一个函数头，然后更新主循环应继续读取的位置。
fn formatFunctionAt(
    allocator: Allocator,
    source_lines: []const []const u8,
    output_lines: *std.ArrayList([]const u8),
    line_index: *usize,
) !void {
    const documentation = try takeFunctionDocumentation(allocator, source_lines[line_index.*], output_lines);
    try appendFunctionSpacing(allocator, output_lines);
    if (documentation) |documentation_lines| {
        try output_lines.appendSlice(allocator, documentation_lines);
    }

    var header: std.ArrayList(u8) = .empty;
    defer header.deinit(allocator);
    try appendText(&header, allocator, source_lines[line_index.*]);

    var next_line = line_index.* + 1;
    const opening = std.mem.indexOfScalar(u8, source_lines[line_index.*], '(') orelse source_lines[line_index.*].len;
    // 函数头允许跨行；只读到参数括号闭合处，避免把函数体并入签名。
    while (syntax.matchingClose(header.items, opening) == null and next_line < source_lines.len) : (next_line += 1) {
        try header.append(allocator, '\n');
        try appendText(&header, allocator, std.mem.trimEnd(u8, source_lines[next_line], " \t"));
    }

    if (try functions.formatHeader(allocator, header.items)) |formatted_header| {
        try output_lines.append(allocator, formatted_header);
    } else {
        // 解析不完整或不受支持时保留原始函数头，不猜测用户代码的意图。
        try output_lines.append(allocator, try allocator.dupe(u8, header.items));
    }
    line_index.* = next_line;
}

/// 规范化普通代码行的缩进，并压缩超过两行的连续空行。
fn appendCodeLine(allocator: Allocator, output_lines: *std.ArrayList([]const u8), line: []const u8) !void {
    try output_lines.append(allocator, try normalizeIndentation(allocator, line));
    while (output_lines.items.len >= 3 and
        std.mem.trim(u8, output_lines.items[output_lines.items.len - 1], " \t").len == 0 and
        std.mem.trim(u8, output_lines.items[output_lines.items.len - 2], " \t").len == 0 and
        std.mem.trim(u8, output_lines.items[output_lines.items.len - 3], " \t").len == 0)
    {
        _ = output_lines.pop();
    }
}

/// 按行完成空白整理、函数签名规范化和文件头声明合并。
fn formatTextInner(allocator: Allocator, source_text: []const u8) ![]u8 {
    const normalized = try std.mem.replaceOwned(u8, allocator, source_text, "\r\n", "\n");
    defer allocator.free(normalized);

    var source_lines: std.ArrayList([]const u8) = .empty;
    defer source_lines.deinit(allocator);
    var raw_lines = std.mem.splitScalar(u8, normalized, '\n');
    while (raw_lines.next()) |line| try source_lines.append(allocator, line);

    var output_lines: std.ArrayList([]const u8) = .empty;
    defer output_lines.deinit(allocator);
    var multiline_quote: u8 = 0;
    var line_index: usize = 0;
    while (line_index < source_lines.items.len) {
        var line = source_lines.items[line_index];
        if (multiline_quote != 0) {
            // 多行字符串中的内容可能长得像代码，必须原样复制并跳过格式规则。
            try output_lines.append(allocator, line);
            const marker: [3]u8 = .{ multiline_quote, multiline_quote, multiline_quote };
            if (std.mem.indexOf(u8, line, &marker) != null) multiline_quote = 0;
            line_index += 1;
            continue;
        }
        if (std.mem.indexOf(u8, line, "\"\"\"") != null) {
            try output_lines.append(allocator, std.mem.trimEnd(u8, line, " \t"));
            if (std.mem.count(u8, line, "\"\"\"") == 1) multiline_quote = '"';
            line_index += 1;
            continue;
        }
        if (std.mem.indexOf(u8, line, "'''") != null) {
            try output_lines.append(allocator, std.mem.trimEnd(u8, line, " \t"));
            if (std.mem.count(u8, line, "'''") == 1) multiline_quote = '\'';
            line_index += 1;
            continue;
        }

        line = std.mem.trimEnd(u8, line, " \t\r");
        if (syntax.isFunction(line)) {
            try formatFunctionAt(allocator, source_lines.items, &output_lines, &line_index);
            continue;
        }

        try appendCodeLine(allocator, &output_lines, line);
        line_index += 1;
    }

    try declarations.formatDeclarations(allocator, &output_lines);
    var result: std.ArrayList(u8) = .empty;
    defer result.deinit(allocator);
    for (output_lines.items, 0..) |line, index| {
        try appendText(&result, allocator, line);
        if (index + 1 < output_lines.items.len) try result.append(allocator, '\n');
    }
    while (result.items.len > 0 and result.items[result.items.len - 1] == '\n') _ = result.pop();
    try result.append(allocator, '\n');
    return try result.toOwnedSlice(allocator);
}

/// 格式化 GDScript 文本并返回新分配的 UTF-8 内容。
pub fn formatText(allocator: Allocator, source_text: []const u8) ![]u8 {
    // 中间行、参数和临时签名共享短生命周期；最终结果复制到调用方的分配器。
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const formatted = try formatTextInner(arena.allocator(), source_text);
    return try allocator.dupe(u8, formatted);
}
