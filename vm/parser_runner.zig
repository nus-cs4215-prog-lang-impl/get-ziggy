const std = @import("std");
const types = @import("types.zig");

pub const ParserRunner = struct {
    allocator: std.mem.Allocator,
    source_file: []const u8,
    source_path: []const u8,

    pub fn init(source_file: []const u8, source_path: []const u8, allocator: std.mem.Allocator) ParserRunner {
        return .{
            .allocator = allocator,
            .source_file = source_file,
            .source_path = source_path,
        };
    }

    pub fn deinit(self: *ParserRunner) !void {
        self.ast.deinit();
    }

    pub fn runCommandAndParseJson(self: *ParserRunner) !void {
        // const in_path = try std.mem.concat(self.allocator, u8, &[_][]const u8{ self.source_path, self.source_file, ".rs" });
        // defer self.allocator.free(in_path);
        //
        // const cmd = &[_][]const u8{ "python", "/app/parser/gen_parse_tree.py", "-f", in_path };
        //
        // var child = std.process.Child.init(cmd, std.heap.page_allocator);
        // try child.spawn();
        // // 2. Wait for child process to finish
        // _ = try child.wait();

        const out_path = try std.mem.concat(self.allocator, u8, &[_][]const u8{ "/app/out_parse/", self.source_file, ".json" });
        defer self.allocator.free(out_path);

        const json_bytes = try std.fs.cwd().readFileAlloc(self.allocator, out_path, 1024 * 1024); // Limit file size
        defer self.allocator.free(json_bytes);
        const r = try std.json.parseFromSlice(types.JsonAstNode, self.allocator, json_bytes, .{ .ignore_unknown_fields = true });
        r.deinit();

        std.debug.print("hi\n", .{});
    }
};

test "test echo" {
    const alloc = std.testing.allocator;
    var pr = ParserRunner.init("literals", "/app/our_examples/", alloc);

    try pr.runCommandAndParseJson();
}
