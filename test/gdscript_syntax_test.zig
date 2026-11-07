const std = @import("std");
const syntax = @import("gdscript_syntax");

// 用例：只按最外层逗号切分，嵌套容器和字符串内容保持在原参数中。
test "嵌套结构与字符串里的逗号不会拆分参数" {
    const params = try syntax.splitParameters(std.testing.allocator, "data: Dictionary = {\"a\": [1, 2]}, name: String = \"x,y\"");
    defer std.testing.allocator.free(params);
    try std.testing.expectEqual(@as(usize, 2), params.len);
    try std.testing.expectEqualStrings("data: Dictionary = {\"a\": [1, 2]}", params[0]);
    try std.testing.expectEqualStrings("name: String = \"x,y\"", params[1]);
}

// 用例：括号扫描忽略字符串内的右括号，定位真正的签名结束处。
test "签名闭合定位会跳过字符串中的右括号" {
    const signature = "func run(text: String = \")\", value: int):";
    const opening = std.mem.indexOfScalar(u8, signature, '(').?;
    const close = syntax.matchingClose(signature, opening).?;
    try std.testing.expectEqual(@as(u8, ')'), signature[close]);
    try std.testing.expectEqualStrings("func run(text: String = \")\", value: int)", signature[0 .. close + 1]);
}
