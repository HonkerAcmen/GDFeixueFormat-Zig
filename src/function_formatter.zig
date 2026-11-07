const std = @import("std");
const Allocator = std.mem.Allocator;
const syntax = @import("gdscript_syntax");

/// 将文本片段追加到正在构造的函数签名中。
fn appendText(list: *std.ArrayList(u8), allocator: Allocator, value: []const u8) Allocator.Error!void {
    try list.appendSlice(allocator, value);
}

/// 判断文本是否包含指定语法标记。
fn containsText(text: []const u8, part: []const u8) bool {
    return std.mem.indexOf(u8, text, part) != null;
}

/// 展开匿名回调的内部参数，同时保留回调签名后面的返回类型和函数体。
fn formatCallback(allocator: Allocator, argument: []const u8, indent: []const u8) !?[]u8 {
    const func_at = std.mem.indexOf(u8, argument, "func(") orelse std.mem.indexOf(u8, argument, "func (") orelse return null;
    const opening = std.mem.indexOfScalarPos(u8, argument, func_at, '(') orelse return null;
    const close = syntax.matchingClose(argument, opening) orelse return null;
    const callback_params = syntax.splitParameters(allocator, argument[opening + 1 .. close]) catch return null;
    defer allocator.free(callback_params);
    if (callback_params.len == 0) return null;
    // 仅处理当前支持的单行回调函数体；无法确认边界时不改写该参数。
    const after = argument[close..];
    if (containsText(after, "\n") or !std.mem.startsWith(u8, std.mem.trimStart(u8, after, " \t"), "):")) return null;

    var output: std.ArrayList(u8) = .empty;
    errdefer output.deinit(allocator);
    try appendText(&output, allocator, indent);
    try appendText(&output, allocator, std.mem.trimEnd(u8, argument[0 .. opening + 1], " \t"));
    try output.append(allocator, '\n');
    for (callback_params, 0..) |param, index| {
        try appendText(&output, allocator, indent);
        try appendText(&output, allocator, "\t");
        try appendText(&output, allocator, param);
        if (index + 1 < callback_params.len) try output.append(allocator, ',');
        try output.append(allocator, '\n');
    }
    try appendText(&output, allocator, indent);
    try appendText(&output, allocator, after);
    return try output.toOwnedSlice(allocator);
}

/// 按参数数量与回调规则格式化一个完整函数头；不需要换行时返回 null。
pub fn formatHeader(allocator: Allocator, header: []const u8) !?[]u8 {
    const func_pos = std.mem.indexOf(u8, header, "func ") orelse return null;
    const opening = std.mem.indexOfScalarPos(u8, header, func_pos, '(') orelse return null;
    const close = syntax.matchingClose(header, opening) orelse return null;
    const params = syntax.splitParameters(allocator, header[opening + 1 .. close]) catch return null;
    defer allocator.free(params);
    if (params.len == 0) return null;

    var has_callback = false;
    for (params) |param| {
        if (containsText(param, "Callable") or containsText(param, "func(") or containsText(param, "func (")) {
            has_callback = true;
            break;
        }
    }
    // 多行输入始终规范化；单行输入只有参数达到阈值或包含回调时才展开。
    if (params.len < 4 and !has_callback and !containsText(header, "\n")) return null;

    const indent_len = header.len - std.mem.trimStart(u8, header, " \t").len;
    const indent = header[0..indent_len];
    var output: std.ArrayList(u8) = .empty;
    errdefer output.deinit(allocator);
    try appendText(&output, allocator, header[0..opening]);
    try output.append(allocator, '(');
    try output.append(allocator, '\n');
    for (params, 0..) |param, index| {
        const param_indent = try std.fmt.allocPrint(allocator, "{s}\t", .{indent});
        if (try formatCallback(allocator, param, param_indent)) |callback| {
            try appendText(&output, allocator, callback);
            if (index + 1 < params.len) try output.append(allocator, ',');
        } else {
            try appendText(&output, allocator, param_indent);
            try appendText(&output, allocator, param);
            if (index + 1 < params.len) try output.append(allocator, ',');
        }
        try output.append(allocator, '\n');
    }
    try appendText(&output, allocator, indent);
    try appendText(&output, allocator, header[close..]);
    return try output.toOwnedSlice(allocator);
}
