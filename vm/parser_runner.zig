const std = @import("std");
const types = @import("types.zig");

pub const ParserRunner = struct {
    allocator: std.mem.Allocator,
    filename: []const u8,

    pub fn init(filename: []const u8, allocator: std.mem.Allocator) ParserRunner {
        return .{
            .allocator = allocator,
            .filename = filename,
        };
    }

    pub fn deinit(self: *ParserRunner) !void {
        self.ast.deinit();
    }

    pub fn runCommandAndParseJson(self: *ParserRunner) !void {
        const cmd = &[_][]const u8{ "python", "parser/gen_parse_tree.py", "-f", self.filename };
        var child = std.process.Child.init(cmd, std.heap.page_allocator);
        try child.spawn();
        // 2. Wait for child process to finish
        _ = try child.wait();

        // const json_bytes = try std.fs.cwd().readFileAlloc(self.allocator, "tests/let_stmt.json", 1024 * 1024); // Limit file size
        // defer self.allocator.free(json_bytes);
        // const r = try std.json.parseFromSlice(types.JsonAstNode, self.allocator, json_bytes, .{ .ignore_unknown_fields = true });
        // r.deinit();
    }
};

test "test echo" {
    const alloc = std.testing.allocator;
    var pr = ParserRunner.init("/app/our_examples/literals.rs", alloc);

    try pr.runCommandAndParseJson();
}
