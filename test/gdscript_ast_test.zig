const std = @import("std");
const ast = @import("gdscript_ast");

// 用例：关键字 lexer 应识别 Godot 4 的声明关键字，避免将其视为普通变量名。
test "Godot 4 声明关键字分类" {
    try std.testing.expect(ast.isKeyword("trait"));
    try std.testing.expect(ast.isKeyword("class_name"));
    try std.testing.expect(ast.isKeyword("signal"));
    try std.testing.expect(ast.isKeyword("await"));
    try std.testing.expect(ast.isKeyword("when"));
    try std.testing.expect(ast.isKeyword("yield"));
    try std.testing.expect(ast.isKeyword("PI"));
    try std.testing.expect(!ast.isKeyword("custom_name"));
}

// 用例：字典字面量和 enum 花括号拥有不同 AST 类型。
test "字典与枚举花括号分别解析" {
    const source = "var mapping = {\n\t\"a\": 1,\n}\nenum State {\n\tIDLE,\n}\n";
    const document = try ast.parse(std.testing.allocator, source);
    defer std.testing.allocator.free(document.tokens);
    defer std.testing.allocator.free(document.nodes);
    defer std.testing.allocator.free(document.containers);
    try std.testing.expectEqual(ast.DelimiterKind.dictionary_literal, document.nodes[0].delimiter.?);
    try std.testing.expectEqual(ast.NodeKind.enumeration, document.nodes[1].kind);
    try std.testing.expectEqual(ast.DelimiterKind.enum_body, document.nodes[1].delimiter.?);
    try std.testing.expectEqual(@as(usize, 2), document.containers.len);
    try std.testing.expectEqual(ast.DelimiterKind.dictionary_literal, document.containers[0].kind);
    try std.testing.expectEqual(ast.DelimiterKind.enum_body, document.containers[1].kind);
}

// 用例：注解、变量和多行续行被拆分为正确语句类别与跨度。
test "注解与反斜杠续行进入语句 AST" {
    const source = "@export_range(0, 10)\nvar speed: float\nvar total = 1 + \\\n\t2\n";
    const document = try ast.parse(std.testing.allocator, source);
    defer std.testing.allocator.free(document.tokens);
    defer std.testing.allocator.free(document.nodes);
    defer std.testing.allocator.free(document.containers);
    try std.testing.expectEqual(ast.NodeKind.annotation, document.nodes[0].kind);
    try std.testing.expectEqual(ast.NodeKind.variable, document.nodes[1].kind);
    try std.testing.expectEqual(@as(usize, 2), document.nodes[2].end_line - document.nodes[2].start_line);
}
