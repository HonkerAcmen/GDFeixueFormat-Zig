const std = @import("std");
const formatter = @import("formatter");

// 用例：输入声明顺序颠倒时，输出仍将两个声明合并并按规范排序。
test "反序 class_name / extends 声明合并并保持 class_name 在前" {
    const actual = try formatter.formatText(std.testing.allocator, "extends Node\nclass_name Example\n");
    defer std.testing.allocator.free(actual);
    try std.testing.expectEqualStrings("class_name Example extends Node\n", actual);
}

// 用例：已经按正确顺序排列的两条声明也会合并为一行。
test "正序 class_name / extends 声明合并为一行" {
    const actual = try formatter.formatText(std.testing.allocator, "class_name Example\nextends Node2D\n");
    defer std.testing.allocator.free(actual);
    try std.testing.expectEqualStrings("class_name Example extends Node2D\n", actual);
}

// 用例：没有父类声明时，不为 class_name 虚构 extends。
test "没有 extends 时保留单独的 class_name" {
    const actual = try formatter.formatText(std.testing.allocator, "class_name Example\n");
    defer std.testing.allocator.free(actual);
    try std.testing.expectEqualStrings("class_name Example\n", actual);
}

// 用例：多行字符串中的相似文本不能被误当成文件头声明。
test "多行字符串里的声明原样保留" {
    const source = "var text = \"\"\"\nclass_name Fake\nextends Node\n\"\"\"\n";
    const actual = try formatter.formatText(std.testing.allocator, source);
    defer std.testing.allocator.free(actual);
    try std.testing.expectEqualStrings(source, actual);
}
