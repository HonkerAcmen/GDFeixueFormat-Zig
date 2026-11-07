// 聚合各职责模块的用例，让 `zig build test` 一次运行整个项目测试集。
test {
    _ = @import("declaration_formatter_test.zig");
    _ = @import("function_formatter_test.zig");
    _ = @import("formatter_test.zig");
    _ = @import("directory_formatter_test.zig");
    _ = @import("gdscript_syntax_test.zig");
    _ = @import("line_statistics_test.zig");
}
