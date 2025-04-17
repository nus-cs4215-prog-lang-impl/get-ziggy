const std = @import("std");
const jsonAst = @import("types.zig").JsonAstNode;
const json = std.json;

pub const ParserRunner = struct {
    allocator: std.mem.Allocator,
    ast: ?json.Parsed(jsonAst),
    // NOTE: json_buffer owns string and other json data
    json_buffer: ?[]u8,

    pub fn init(allocator: std.mem.Allocator) ParserRunner {
        return .{
            .allocator = allocator,
            .ast = null,
            .json_buffer = null,
        };
    }

    pub fn deinit(self: *ParserRunner) void {
        self.ast.?.deinit();
        self.allocator.free(self.json_buffer.?);
    }

    pub fn parseRustParseJson(self: *ParserRunner, source_file: []const u8, source_path: []const u8) !jsonAst {
        // const in_path = try std.mem.concat(self.allocator, u8, &[_][]const u8{ source_path, source_file, ".rs" });
        // defer self.allocator.free(in_path);
        //
        // const cmd = &[_][]const u8{ "python", "/app/parser/gen_parse_tree.py", "-f", in_path };
        //
        // var child = std.process.Child.init(cmd, std.heap.page_allocator);
        // try child.spawn();
        // // 2. Wait for child process to finish
        // _ = try child.wait();
        _ = source_path;

        const out_path = try std.mem.concat(self.allocator, u8, &[_][]const u8{ "/app/out_parse/", source_file, ".json" });
        defer self.allocator.free(out_path);

        self.json_buffer = try std.fs.cwd().readFileAlloc(self.allocator, out_path, 1024 * 1024); // Limit file size
        self.ast = try json.parseFromSlice(jsonAst, self.allocator, self.json_buffer.?, .{ .ignore_unknown_fields = true });

        const val = self.ast.?.value;

        return val;
    }
};

test "test basic run python parser and read json ast" {
    const alloc = std.testing.allocator;

    var pr = ParserRunner.init(alloc);
    var jsonNodes = try pr.parseRustParseJson("literals", "/app/our_examples/");
    defer pr.deinit();

    _ = &jsonNodes;

    var compiler = @import("compiler.zig").Compiler.init(alloc);
    defer compiler.deinit();

    try compiler.compileProgram(&jsonNodes);
    try compiler.printCompiledMicrocode();
}
