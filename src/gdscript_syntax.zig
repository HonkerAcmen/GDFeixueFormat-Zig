const std = @import("std");
const Allocator = std.mem.Allocator;

/// 判断右括号是否与当前栈顶的左括号配对。
fn matches(open: u8, close: u8) bool {
    return (open == '(' and close == ')') or (open == '[' and close == ']') or (open == '{' and close == '}');
}

/// 找出函数参数括号的闭合位置，忽略字符串和注释中的括号。
pub fn matchingClose(text: []const u8, opening: usize) ?usize {
    // 函数签名的括号层级通常很浅；固定栈可避免解析时反复分配内存。
    // 超过容量或括号不配对时返回 null，由上层保留原始文本。
    var stack: [256]u8 = undefined;
    var depth: usize = 0;
    var quote: u8 = 0;
    var escaped = false;
    var index = opening;
    while (index < text.len) : (index += 1) {
        const char = text[index];
        if (quote != 0) {
            if (escaped) {
                escaped = false;
            } else if (char == '\\') {
                escaped = true;
            } else if (char == quote) {
                quote = 0;
            }
            continue;
        }
        if (char == '#' and depth == 0) {
            while (index < text.len and text[index] != '\n') : (index += 1) {}
            continue;
        }
        if (char == '"' or char == '\'') {
            quote = char;
        } else if (char == '(' or char == '[' or char == '{') {
            if (depth == stack.len) return null;
            stack[depth] = char;
            depth += 1;
        } else if (char == ')' or char == ']' or char == '}') {
            if (depth == 0 or !matches(stack[depth - 1], char)) return null;
            depth -= 1;
            if (depth == 0) return index;
        }
    }
    return null;
}

/// 按顶层逗号切分参数，保留字符串及嵌套表达式内部的逗号。
pub fn splitParameters(allocator: Allocator, text: []const u8) ![][]const u8 {
    var params: std.ArrayList([]const u8) = .empty;
    errdefer params.deinit(allocator);
    // 只在最外层逗号处切分，括号和引号里的逗号属于参数表达式本身。
    var stack: [256]u8 = undefined;
    var depth: usize = 0;
    var quote: u8 = 0;
    var escaped = false;
    var start: usize = 0;

    for (text, 0..) |char, index| {
        if (quote != 0) {
            if (escaped) {
                escaped = false;
            } else if (char == '\\') {
                escaped = true;
            } else if (char == quote) {
                quote = 0;
            }
            continue;
        }
        if (char == '#') return error.UnsupportedComment;
        if (char == '"' or char == '\'') {
            quote = char;
        } else if (char == '(' or char == '[' or char == '{') {
            if (depth == stack.len) return error.InvalidSignature;
            stack[depth] = char;
            depth += 1;
        } else if (char == ')' or char == ']' or char == '}') {
            if (depth == 0 or !matches(stack[depth - 1], char)) return error.InvalidSignature;
            depth -= 1;
        } else if (char == ',' and depth == 0) {
            const part = std.mem.trim(u8, text[start..index], " \t\r\n");
            if (part.len == 0) return error.InvalidSignature;
            try params.append(allocator, part);
            start = index + 1;
        }
    }
    if (quote != 0 or depth != 0) return error.InvalidSignature;
    const tail = std.mem.trim(u8, text[start..], " \t\r\n");
    if (tail.len != 0) try params.append(allocator, tail);
    return try params.toOwnedSlice(allocator);
}

/// 判断一行是否以 GDScript 普通函数或静态函数声明开头。
pub fn isFunction(line: []const u8) bool {
    const trimmed = std.mem.trimStart(u8, line, " \t");
    return std.mem.startsWith(u8, trimmed, "func ") or std.mem.startsWith(u8, trimmed, "static func ");
}
