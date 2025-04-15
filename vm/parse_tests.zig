const std = @import("std");
const testing = std.testing;
const json = std.json;
const fs = std.fs;
const types = @import("types.zig");
const compile = @import("compiler.zig");

const Value = types.Value;
const UnaryOperator = types.UnaryOperator;
const BinaryOperator = types.BinaryOperator;
const LogicalOperator = types.LogicalOperator;
const Param = types.Param;
const CompileErrors = types.CompileErrors;
const AstNode = types.AstNode;
const JsonAstNode = types.JsonAstNode;
const Instruction = types.Instruction;

test "serialize JsonAstNode to JSON" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    // Test case 1: Literal node (integer)
    {
        const node = JsonAstNode{
            .lit = .{ .val = .{ .Int = 42 } },
        };

        var string = std.ArrayList(u8).init(allocator);
        defer string.deinit();

        try json.stringify(node, .{}, string.writer());

        const result = string.items;
        std.debug.print("\nSerialized lit JSON: {s}\n", .{result});
        try testing.expect(std.mem.indexOf(u8, result, "\"lit\"") != null);
        try testing.expect(std.mem.indexOf(u8, result, "\"val\"") != null);
        try testing.expect(std.mem.indexOf(u8, result, "\"Int\"") != null);
        try testing.expect(std.mem.indexOf(u8, result, "42") != null);
    }

    // Test case 2: Name node
    {
        const name = try allocator.dupe(u8, "testVar");
        const node = JsonAstNode{
            .nam = name,
        };

        var string = std.ArrayList(u8).init(allocator);
        defer string.deinit();

        try json.stringify(node, .{}, string.writer());

        const result = string.items;
        std.debug.print("\nSerialized nam JSON: {s}\n", .{result});
        try testing.expect(std.mem.indexOf(u8, result, "\"nam\"") != null);
        try testing.expect(std.mem.indexOf(u8, result, "\"testVar\"") != null);
    }

    // Test case 3: Arithmetic operation node
    {
        const left = try allocator.create(JsonAstNode);
        left.* = JsonAstNode{ .lit = .{ .val = .{ .Int = 10 } } };

        const right = try allocator.create(JsonAstNode);
        right.* = JsonAstNode{ .lit = .{ .val = .{ .Int = 20 } } };

        const node = JsonAstNode{
            .arith = .{
                .sym = BinaryOperator{ .arith = .Add },
                .first = left,
                .second = right,
            },
        };

        var string = std.ArrayList(u8).init(allocator);
        defer string.deinit();

        try json.stringify(node, .{}, string.writer());

        const result = string.items;
        std.debug.print("\nSerialized arith JSON: {s}\n", .{result});
        try testing.expect(std.mem.indexOf(u8, result, "\"arith\"") != null);
        try testing.expect(std.mem.indexOf(u8, result, "\"sym\":\"+\"") != null);
        try testing.expect(std.mem.indexOf(u8, result, "\"first\"") != null);
        try testing.expect(std.mem.indexOf(u8, result, "\"second\"") != null);
        try testing.expect(std.mem.indexOf(u8, result, "10") != null);
        try testing.expect(std.mem.indexOf(u8, result, "20") != null);
    }
}

test "parse JSON to JsonAstNode" {
    // var arena = std.heap.ArenaAllocator.init(testing.allocator);
    // defer arena.deinit();
    // const allocator = arena.allocator();

    // Test case 1: Parse a literal node
    {
        // NOTE: JSON structure needs to match JsonAstNode definition
        const json_str =
            \\{"lit":{"val":{"Int":42}}}
        ;

        const item = try json.parseFromSlice(JsonAstNode, testing.allocator, json_str, .{});
        defer item.deinit();
        std.debug.print("Parsed item: {}\n", .{item.value});

        try testing.expectEqual(JsonAstNode.lit, std.meta.activeTag(item.value));
        try testing.expectEqual(Value.Int, std.meta.activeTag(item.value.lit.val));
        try testing.expectEqual(@as(i64, 42), item.value.lit.val.Int);
    }

    // Test case 2: Parse a name node
    {
        const json_str =
            \\{ "nam":"testVar"}
        ;

        const item = try json.parseFromSlice(JsonAstNode, testing.allocator, json_str, .{});
        defer item.deinit();
        std.debug.print("Parsed item: {}\n", .{item.value});

        try testing.expectEqual(JsonAstNode.nam, std.meta.activeTag(item.value));
        try testing.expectEqualStrings("testVar", item.value.nam);
    }

    // Test case 3: Parse an arithmetic operation
    {
        // NOTE: JSON structure needs to match JsonAstNode definition
        const json_str =
            \\{
            \\  "arith": {
            \\    "sym": "+",
            \\    "first": {"lit": {"val": {"Int": 10}}},
            \\    "second": {"lit": {"val": {"Int": 20}}}
            \\  }
            \\}
        ;

        const item = try json.parseFromSlice(JsonAstNode, testing.allocator, json_str, .{});
        defer item.deinit();
        std.debug.print("Parsed item: {}\n", .{item.value});

        try testing.expectEqual(JsonAstNode.arith, std.meta.activeTag(item.value));
        try testing.expectEqual(BinaryOperator{ .arith = .Add }, item.value.arith.sym);

        // NOTE: JsonAstNode.arith contains *AstNode pointers
        const first = item.value.arith.first;
        try testing.expectEqual(JsonAstNode.lit, std.meta.activeTag(first.*));
        try testing.expectEqual(@as(i64, 10), first.*.lit.val.Int);

        const second = item.value.arith.second;
        try testing.expectEqual(JsonAstNode.lit, std.meta.activeTag(second.*));
        try testing.expectEqual(@as(i64, 20), second.*.lit.val.Int);
    }

    {
        const json_str =
            \\{
            \\  "arith": {
            \\    "sym": "+",
            \\    "first": {"lit": {"val": {"Int": 10}}},
            \\    "second": {"lit": {"val": {"Int": 20}}}
            \\  }
            \\}
        ;

        const item = try json.parseFromSlice(JsonAstNode, testing.allocator, json_str, .{});
        defer item.deinit();
        std.debug.print("Parsed item: {}\n", .{item.value});

        try testing.expectEqual(JsonAstNode.arith, std.meta.activeTag(item.value));
        try testing.expectEqual(BinaryOperator{ .arith = .Add }, item.value.arith.sym);

        // NOTE: JsonAstNode.arith contains *AstNode pointers
        const first = item.value.arith.first;
        try testing.expectEqual(JsonAstNode.lit, std.meta.activeTag(first.*));
        try testing.expectEqual(@as(i64, 10), first.*.lit.val.Int);

        const second = item.value.arith.second;
        try testing.expectEqual(JsonAstNode.lit, std.meta.activeTag(second.*));
        try testing.expectEqual(@as(i64, 20), second.*.lit.val.Int);
    }
}

test "round trip JsonAstNode to JSON and back" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    // Create a complex JsonAstNode node
    const left_ast = try allocator.create(JsonAstNode);
    left_ast.* = JsonAstNode{ .lit = .{ .val = .{ .Int = 10 } } };

    const right_ast = try allocator.create(JsonAstNode);
    const var_name = try allocator.dupe(u8, "x");
    right_ast.* = JsonAstNode{ .nam = var_name };

    const original_node = JsonAstNode{
        .arith = .{
            .sym = BinaryOperator{ .arith = .Add },
            .first = left_ast,
            .second = right_ast,
        },
    };

    // Serialize to JSON
    var json_string = std.ArrayList(u8).init(allocator);
    defer json_string.deinit();

    try json.stringify(original_node, .{}, json_string.writer());

    // Print the JSON for debugging
    std.debug.print("Serialized JSON: {s}\n", .{json_string.items});

    // Parse the JSON back to a JsonAstNode
    const parsed = try json.parseFromSlice(JsonAstNode, allocator, json_string.items, .{});
    defer parsed.deinit();

    // Verify the structure is preserved
    try testing.expectEqual(JsonAstNode.arith, std.meta.activeTag(parsed.value));
    try testing.expectEqual(BinaryOperator{ .arith = .Add }, parsed.value.arith.sym);

    // Check first node (should be a literal with value 10)
    const parsed_first = parsed.value.arith.first;
    try testing.expectEqual(JsonAstNode.lit, std.meta.activeTag(parsed_first.*));
    try testing.expectEqual(Value.Int, std.meta.activeTag(parsed_first.*.lit.val));
    try testing.expectEqual(@as(i64, 10), parsed_first.*.lit.val.Int);

    // Check second node (should be a name with value "x")
    const parsed_second = parsed.value.arith.second;
    try testing.expectEqual(JsonAstNode.nam, std.meta.activeTag(parsed_second.*));
    try testing.expectEqualStrings("x", parsed_second.*.nam);
}

test "parse literals.json" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    // 1. Read the JSON file content
    const json_bytes = try std.fs.cwd().readFileAlloc(allocator, "tests/literals.json", 1024 * 1024); // Limit file size
    defer allocator.free(json_bytes);

    // 2. Parse the JSON into JsonAstNode
    const parsed_node = try json.parseFromSlice(JsonAstNode, allocator, json_bytes, .{ .ignore_unknown_fields = true }); // Ignore the trailing "" in stmts
    defer parsed_node.deinit();

    std.debug.print("Parsed item: {}\n", .{parsed_node.value});

    // 3. Verify the structure
    // Root -> blk
    // try testing.expectEqual(JsonAstNode.blk, std.meta.activeTag(parsed_node.value));
    // const root_blk = parsed_node.value.blk;

    // // blk -> body -> seq
    // try testing.expectEqual(JsonAstNode.seq, std.meta.activeTag(root_blk.body.*));
    // const root_seq = root_blk.body.*.seq;

    // // seq -> stmts[0] -> fun (main)
    // try testing.expect(root_seq.stmts.len > 0);
    // try testing.expectEqual(JsonAstNode.fun, std.meta.activeTag(root_seq.stmts[0].*));
    // const main_fun = root_seq.stmts[0].*.fun;
    // try testing.expectEqualStrings("main", main_fun.nam);

    // // fun -> body -> blk
    // try testing.expectEqual(JsonAstNode.blk, std.meta.activeTag(main_fun.body.*));
    // const main_body_blk = main_fun.body.*.blk;

    // // blk -> body -> seq
    // try testing.expectEqual(JsonAstNode.seq, std.meta.activeTag(main_body_blk.body.*));
    // const main_body_seq = main_body_blk.body.*.seq;

    // // seq -> stmts (the literals)
    // const literal_stmts = main_body_seq.stmts;
    // try testing.expectEqual(@as(usize, 7), literal_stmts.len); // Expect 7 literal statements

    // // Verify each literal statement
    // const expected_literals = [_][]const u8{
    //     "\"hello\"",
    //     "'a'",
    //     "1",
    //     "3.14",
    //     "true",
    //     "123u32",
    //     "123_u32",
    // };

    // for (literal_stmts, 0..) |stmt_ptr, i| {
    //     const stmt = stmt_ptr.*;
    //     try testing.expectEqual(JsonAstNode.lit, std.meta.activeTag(stmt));
    //     const literal_node = stmt.lit;
    //     // NOTE: As discussed, std.json likely parses the "val": "..." as Value.String
    //     // because the JSON value itself is a string.
    //     try testing.expectEqual(Value.String, std.meta.activeTag(literal_node.val));
    //     try testing.expectEqualStrings(expected_literals[i], literal_node.val.String);
    // }
}
