const std = @import("std");
const Allocator = std.mem.Allocator;
const syntax = @import("gdscript_syntax");
const declarations = @import("declaration_formatter");
const functions = @import("function_formatter");
const comments = @import("comment_formatter");
const ast = @import("gdscript_ast");

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
    has_annotation: bool,
) !void {
    const documentation = try takeFunctionDocumentation(allocator, source_lines[line_index.*], output_lines);
    if (!has_annotation) try appendFunctionSpacing(allocator, output_lines);
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

/// 生成指定缩进层级的 Tab 前缀，统一用于容器与表达式续行。
fn makeIndentation(allocator: Allocator, base: []const u8, extra_levels: usize) ![]u8 {
    var indentation: std.ArrayList(u8) = .empty;
    try indentation.appendSlice(allocator, base);
    for (0..extra_levels) |_| try indentation.append(allocator, '\t');
    return try indentation.toOwnedSlice(allocator);
}

/// 检查回调代码块中的分支是否以 return、continue 或 break 结束。
fn callbackBranchTerminates(
    source_lines: []const []const u8,
    header_line: usize,
    header_indent_depth: usize,
) bool {
    for (header_line + 1..source_lines.len) |line_index| {
        const line = source_lines[line_index];
        const content = std.mem.trim(u8, line, " \t\r");
        if (content.len == 0) continue;
        if (ast.indentationDepth(line) <= header_indent_depth) break;

        const statement = std.mem.trimStart(u8, content, " \t");
        if (std.mem.startsWith(u8, statement, "return") or
            std.mem.startsWith(u8, statement, "continue") or
            std.mem.startsWith(u8, statement, "break")) return true;
    }
    return false;
}

/// 找到后续第一条非空行，回调和调用括号之间允许保留空行。
fn nextNonBlankContent(source_lines: []const []const u8, start_line: usize) []const u8 {
    for (source_lines[start_line..]) |line| {
        const content = std.mem.trim(u8, line, " \t\r");
        if (content.len > 0) return content;
    }
    return "";
}

/// 按 AST 的分隔符类型重新缩进多行容器或表达式续行。
fn appendParsedNode(
    allocator: Allocator,
    output_lines: *std.ArrayList([]const u8),
    source_lines: []const []const u8,
    node: ast.Node,
    containers: []const ast.ContainerNode,
) !void {
    const first_line = source_lines[node.start_line];
    const base_indent = try normalizeIndentation(allocator, first_line);
    const normalized_base_length = base_indent.len - std.mem.trimStart(u8, base_indent, " \t").len;
    const normalized_base = base_indent[0..normalized_base_length];
    var inside_anonymous_callback = false;
    var callback_header_indent_depth: usize = 0;
    var callback_header_continuation_levels: usize = 0;
    for (node.start_line..node.end_line) |line_index| {
        const line = source_lines[line_index];
        if (line_index == node.start_line) {
            try output_lines.append(allocator, base_indent);
            continue;
        }
        const content = std.mem.trim(u8, line, " \t\r");
        if (content.len == 0) {
            try output_lines.append(allocator, "");
            continue;
        }
        var continuation_levels: usize = 2;
        if (node.delimiter != null) {
            continuation_levels = 0;
            for (containers) |container| {
                if (container.start_line >= line_index or container.end_line <= line_index) continue;
                continuation_levels += switch (container.kind) {
                    .parentheses => 2,
                    .array_literal, .dictionary_literal, .enum_body => 1,
                };
            }
        } else if (node.kind == .annotation or node.kind == .comment) {
            continuation_levels = 0;
        }
        const previous_line = source_lines[line_index - 1];
        const previous_content = std.mem.trimEnd(u8, previous_line, " \t\r");
        const follows_backslash = node.has_backslash_continuation and previous_content.len > 0 and previous_content[previous_content.len - 1] == '\\';
        const is_chain_call = node.has_chain_call and (std.mem.startsWith(u8, content, ".") or std.mem.startsWith(u8, content, "?."));
        if (follows_backslash or is_chain_call) continuation_levels = 2;
        const is_callback_header = (std.mem.startsWith(u8, content, "func (") or std.mem.startsWith(u8, content, "func(")) and
            std.mem.endsWith(u8, content, "):");
        const source_indent_depth = ast.indentationDepth(line);
        const callback_statement = std.mem.trimEnd(u8, content, " \\");
        const is_callback_if_header = inside_anonymous_callback and
            std.mem.startsWith(u8, content, "if ") and std.mem.endsWith(u8, callback_statement, ":");
        if (inside_anonymous_callback) {
            // 代码块的相对缩进决定语义，不能根据 return 等语句猜测分支边界。
            const callback_extra_indent = source_indent_depth -| callback_header_indent_depth;
            continuation_levels = callback_header_continuation_levels + callback_extra_indent;
        }
        const indentation = try makeIndentation(allocator, normalized_base, continuation_levels);
        const next_content = nextNonBlankContent(source_lines, line_index + 1);
        const callback_branch_terminates = is_callback_if_header and
            callbackBranchTerminates(source_lines, line_index, source_indent_depth);
        const formatted_content = if (callback_branch_terminates and std.mem.endsWith(u8, content, "\\"))
            std.mem.trimEnd(u8, content, " \\")
        else
            content;
        const needs_suite_continuation = inside_anonymous_callback and
            std.mem.endsWith(u8, callback_statement, ":") and !callback_branch_terminates;
        const ends_callback_before_call_close = inside_anonymous_callback and
            (std.mem.eql(u8, next_content, ")") or std.mem.eql(u8, next_content, "),"));
        const needs_callback_continuation = needs_suite_continuation or ends_callback_before_call_close;
        const continuation_suffix: []const u8 = if (needs_callback_continuation and !std.mem.endsWith(u8, formatted_content, "\\")) " \\" else "";
        const formatted_line = try std.fmt.allocPrint(allocator, "{s}{s}{s}", .{ indentation, formatted_content, continuation_suffix });
        try output_lines.append(allocator, formatted_line);
        if (is_callback_header) {
            inside_anonymous_callback = true;
            callback_header_indent_depth = source_indent_depth;
            callback_header_continuation_levels = continuation_levels;
        }
        if (ends_callback_before_call_close) inside_anonymous_callback = false;
    }
}

/// 在同级成员声明组之间保留一个空行；注解与被注解声明始终相邻。
fn appendMemberGroupSpacing(
    allocator: Allocator,
    output_lines: *std.ArrayList([]const u8),
    previous: ?ast.Node,
    current: ast.Node,
    nodes: []const ast.Node,
) !void {
    const previous_node = previous orelse return;
    if (current.kind == .enumeration and previous_node.kind == .comment) return;
    var blank_lines: usize = 0;
    // 进入控制流代码块时，子节点与块头相邻；只有缩进回退离开函数作用域才补空行。
    if (previous_node.parent != current.parent and current.indent <= previous_node.indent) {
        if (previous_node.parent) |parent_index| {
            const parent_kind = nodes[parent_index].kind;
            if (parent_kind == .function or parent_kind == .class_declaration) blank_lines = 2;
        }
    } else if (previous_node.indent == current.indent and
        (previous_node.kind == .function or previous_node.kind == .class_declaration or
            current.kind == .function or current.kind == .class_declaration))
    {
        blank_lines = 2;
    }
    const current_is_group = current.kind == .enumeration or current.kind == .signal;
    const previous_is_group = previous_node.kind == .enumeration or previous_node.kind == .signal;
    if (blank_lines == 0 and previous_node.parent == current.parent and previous_node.indent == current.indent and
        (current_is_group or previous_is_group)) blank_lines = 1;
    if (blank_lines == 0) return;
    while (output_lines.items.len > 0 and ast.classifyLine(output_lines.items[output_lines.items.len - 1]) == .blank) {
        _ = output_lines.pop();
    }
    for (0..blank_lines) |_| try output_lines.append(allocator, "");
}

/// 检查 AST 前一节点是否为独立注解，后续声明需要紧贴该注解块。
fn previousNodeIsAnnotation(previous: ?ast.Node) bool {
    return if (previous) |node| node.kind == .annotation else false;
}

/// 跳过连续注解、空行和说明注释，判断注解块是否修饰函数。
fn annotationBlockTargetsFunction(nodes: []const ast.Node, start_index: usize) bool {
    var index = start_index + 1;
    while (index < nodes.len and
        (nodes[index].kind == .annotation or nodes[index].kind == .blank or nodes[index].kind == .comment)) : (index += 1)
    {}
    return index < nodes.len and nodes[index].kind == .function;
}

/// 按行完成空白整理、函数签名规范化和文件头声明合并。
fn formatTextInner(allocator: Allocator, source_text: []const u8) ![]u8 {
    const normalized = try std.mem.replaceOwned(u8, allocator, source_text, "\r\n", "\n");
    defer allocator.free(normalized);
    const document = try ast.parse(allocator, normalized);
    defer allocator.free(document.tokens);
    defer allocator.free(document.nodes);
    defer allocator.free(document.containers);
    if (!document.syntax_valid) {
        // 无法建立合法语法树时不执行部分格式化，防止错误输入被重排。
        return try allocator.dupe(u8, normalized);
    }

    var source_lines: std.ArrayList([]const u8) = .empty;
    defer source_lines.deinit(allocator);
    var raw_lines = std.mem.splitScalar(u8, normalized, '\n');
    while (raw_lines.next()) |line| try source_lines.append(allocator, line);

    var output_lines: std.ArrayList([]const u8) = .empty;
    defer output_lines.deinit(allocator);
    var multiline_quote: u8 = 0;
    var line_index: usize = 0;
    var node_index: usize = 0;
    var previous_node: ?ast.Node = null;
    var pending_annotation = false;
    while (line_index < source_lines.items.len) {
        while (node_index < document.nodes.len and document.nodes[node_index].end_line <= line_index) node_index += 1;
        if (node_index >= document.nodes.len) break;
        const node = document.nodes[node_index];
        if (node.start_line != line_index) {
            line_index += 1;
            continue;
        }
        var line = source_lines.items[line_index];
        if (pending_annotation and node.kind == .blank) {
            line_index += 1;
            node_index += 1;
            continue;
        }
        if (node.kind == .blank) {
            const previous_opens_suite = if (previous_node) |previous| previous.opens_suite else false;
            var next_node_index = node_index + 1;
            while (next_node_index < document.nodes.len and document.nodes[next_node_index].kind == .blank) : (next_node_index += 1) {}
            var previous_node_index = node_index;
            while (previous_node_index > 0 and document.nodes[previous_node_index - 1].kind == .blank) : (previous_node_index -= 1) {}
            if (previous_node_index > 0) previous_node_index -= 1;
            const previous_is_comment = previous_node_index < document.nodes.len and
                document.nodes[previous_node_index].kind == .comment;
            const next_is_enum = next_node_index < document.nodes.len and
                document.nodes[next_node_index].kind == .enumeration;
            if (previous_is_comment and next_is_enum) {
                // 标题注释和枚举文档必须紧贴枚举声明，不保留它们之间的空行。
                line_index += 1;
                node_index += 1;
                continue;
            }
            const next_is_suite_child = previous_opens_suite and next_node_index < document.nodes.len and
                document.nodes[next_node_index].parent == previous_node_index;
            if (previous_opens_suite and next_is_suite_child) {
                line_index += 1;
                node_index += 1;
                continue;
            }
        }
        if (multiline_quote != 0) {
            // 多行字符串中的内容可能长得像代码，必须原样复制并跳过格式规则。
            try output_lines.append(allocator, line);
            const marker: [3]u8 = .{ multiline_quote, multiline_quote, multiline_quote };
            if (std.mem.indexOf(u8, line, &marker) != null) multiline_quote = 0;
            line_index += 1;
            previous_node = node;
            node_index += 1;
            continue;
        }
        if (std.mem.indexOf(u8, line, "\"\"\"") != null) {
            try output_lines.append(allocator, std.mem.trimEnd(u8, line, " \t"));
            if (std.mem.count(u8, line, "\"\"\"") == 1) multiline_quote = '"';
            line_index += 1;
            previous_node = node;
            node_index += 1;
            continue;
        }
        if (std.mem.indexOf(u8, line, "'''") != null) {
            try output_lines.append(allocator, std.mem.trimEnd(u8, line, " \t"));
            if (std.mem.count(u8, line, "'''") == 1) multiline_quote = '\'';
            line_index += 1;
            previous_node = node;
            node_index += 1;
            continue;
        }

        line = std.mem.trimEnd(u8, line, " \t\r");
        if (node.kind == .function) {
            const has_annotation = pending_annotation or previousNodeIsAnnotation(previous_node);
            if (!has_annotation) try appendMemberGroupSpacing(allocator, &output_lines, previous_node, node, document.nodes);
            try formatFunctionAt(allocator, source_lines.items, &output_lines, &line_index, has_annotation);
            previous_node = node;
            node_index += 1;
            pending_annotation = false;
            continue;
        }
        if (node.kind == .annotation) {
            if (!pending_annotation and annotationBlockTargetsFunction(document.nodes, node_index)) {
                try appendFunctionSpacing(allocator, &output_lines);
            }
            pending_annotation = true;
        } else if (node.kind != .comment and node.kind != .blank) {
            pending_annotation = false;
            try appendMemberGroupSpacing(allocator, &output_lines, previous_node, node, document.nodes);
        }
        if (node.end_line - node.start_line > 1) {
            try appendParsedNode(allocator, &output_lines, source_lines.items, node, document.containers);
            line_index = node.end_line;
        } else {
            try appendCodeLine(allocator, &output_lines, line);
            line_index += 1;
        }
        previous_node = node;
        node_index += 1;
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
