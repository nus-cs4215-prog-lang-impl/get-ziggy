const std = @import("std");
const testing = std.testing;
const json = std.json;
const fs = std.fs;
const types = @import("types.zig");
const compile = @import("compiler.zig");

const LiteralVal = types.LiteralVal; // Use LiteralVal
const TypeName = types.TypeName; // Import TypeName
const UnaryOperator = types.UnaryOperator;
const BinaryOperator = types.BinaryOperator;
const LogicalOperator = types.LogicalOperator;
const Param = types.Param;
const CompileErrors = types.CompileErrors;
const AstNode = types.AstNode; // Keep if still used elsewhere, otherwise remove
const JsonAstNode = types.JsonAstNode;
const Instruction = types.Instruction;

test "serialize JsonAstNode to JSON" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    // Test case 1: Literal node (integer) using LiteralVal
    {
        const node = JsonAstNode{
            .lit = .{ .val = "42", .type_name = .i32 }, // Use LiteralVal structure
        };

        var string = std.ArrayList(u8).init(allocator);
        defer string.deinit();

        try json.stringify(node, .{}, string.writer());

        const result = string.items;
        std.debug.print("\nSerialized lit JSON: {s}\n", .{result});
        // Check for new structure
        try testing.expect(std.mem.indexOf(u8, result, "\"lit\"") != null);
        try testing.expect(std.mem.indexOf(u8, result, "\"val\":\"42\"") != null); // Check string value
        try testing.expect(std.mem.indexOf(u8, result, "\"type_name\":\"i32\"") != null); // Check type name
    }

    // Test case 2: Name node (remains the same)
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

    // Test case 3: Arithmetic operation node with LiteralVal
    {
        const left = try allocator.create(JsonAstNode);
        left.* = JsonAstNode{ .lit = .{ .val = "10", .type_name = .i32 } }; // Use LiteralVal

        const right = try allocator.create(JsonAstNode);
        right.* = JsonAstNode{ .lit = .{ .val = "20", .type_name = .i32 } }; // Use LiteralVal

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
        // Check for LiteralVal structure within the arithmetic node
        try testing.expect(std.mem.indexOf(u8, result, "\"val\":\"10\"") != null);
        try testing.expect(std.mem.indexOf(u8, result, "\"type_name\":\"i32\"") != null);
        try testing.expect(std.mem.indexOf(u8, result, "\"val\":\"20\"") != null);
    }

    // Test case 4: Assignment node with arithmetic expression
    {
        // lhs: "result"
        const lhs_name = try allocator.dupe(u8, "result");

        // rhs: 10 + 20
        const first_lit = try allocator.create(JsonAstNode);
        first_lit.* = JsonAstNode{ .lit = .{ .val = "10", .type_name = .i32 } };

        const second_lit = try allocator.create(JsonAstNode);
        second_lit.* = JsonAstNode{ .lit = .{ .val = "20", .type_name = .i32 } };

        const rhs_node = try allocator.create(JsonAstNode);
        rhs_node.* = JsonAstNode{
            .arith = .{
                .sym = BinaryOperator{ .arith = .Add },
                .first = first_lit,
                .second = second_lit,
            },
        };

        // lhs node: "result"
        const lhs_node = try allocator.create(JsonAstNode);
        lhs_node.* = JsonAstNode{ .nam = lhs_name };

        // compound assign node: result += (10 + 20)
        const node = JsonAstNode{
            .compound_assign = .{
                .sym = BinaryOperator{ .compound_assign = .AddAssign }, // e.g., +=
                .first = lhs_node, // The variable name node
                .second = rhs_node, // The arithmetic expression node
            },
        };

        var string = std.ArrayList(u8).init(allocator);
        defer string.deinit();

        try json.stringify(node, .{}, string.writer());

        const result = string.items;
        // Print the resulting JSON string
        std.debug.print("\nSerialized compound_assign JSON: {s}\n", .{result});
    }
}

test "parse JSON to JsonAstNode" {
    // var arena = std.heap.ArenaAllocator.init(testing.allocator);
    // defer arena.deinit();
    // const allocator = arena.allocator();

    // Test case 1: Parse a literal node with LiteralVal structure
    {
        // NOTE: JSON structure needs to match LiteralVal definition
        const json_str =
            \\{"lit":{"val":"42", "type_name":"i32"}}
        ;

        const item = try json.parseFromSlice(JsonAstNode, testing.allocator, json_str, .{});
        defer item.deinit();
        std.debug.print("Parsed item: {}\n", .{item.value});

        try testing.expectEqual(JsonAstNode.lit, std.meta.activeTag(item.value));
        // Check LiteralVal fields
        try testing.expectEqual(types.TypeName.i32, item.value.lit.type_name);
        try testing.expectEqualStrings("42", item.value.lit.val);
    }

    // Test case 2: Parse a name node (remains the same)
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

    // Test case 3: Parse an arithmetic operation with LiteralVal
    {
        // NOTE: JSON structure needs to match LiteralVal definition inside
        const json_str =
            \\{
            \\  "arith": {
            \\    "sym": "+",
            \\    "first": {"lit": {"val": "10", "type_name": "i32"}},
            \\    "second": {"lit": {"val": "20", "type_name": "i32"}}
            \\  }
            \\}
        ;

        const item = try json.parseFromSlice(JsonAstNode, testing.allocator, json_str, .{});
        defer item.deinit();
        std.debug.print("Parsed item: {}\n", .{item.value});

        try testing.expectEqual(JsonAstNode.arith, std.meta.activeTag(item.value));
        try testing.expectEqual(BinaryOperator{ .arith = .Add }, item.value.arith.sym);

        // Check first node (should be a literal with value "10" and type i32)
        const first = item.value.arith.first;
        try testing.expectEqual(JsonAstNode.lit, std.meta.activeTag(first.*));
        try testing.expectEqual(types.TypeName.i32, first.*.lit.type_name);
        try testing.expectEqualStrings("10", first.*.lit.val);

        // Check second node (should be a literal with value "20" and type i32)
        const second = item.value.arith.second;
        try testing.expectEqual(JsonAstNode.lit, std.meta.activeTag(second.*));
        try testing.expectEqual(types.TypeName.i32, second.*.lit.type_name);
        try testing.expectEqualStrings("20", second.*.lit.val);
    }

    // Duplicate test case 3 removed as it was identical
}

test "round trip JsonAstNode to JSON and back" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    // Create a complex JsonAstNode node using LiteralVal
    const left_ast = try allocator.create(JsonAstNode);
    left_ast.* = JsonAstNode{ .lit = .{ .val = "10", .type_name = .i32 } }; // Use LiteralVal

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

    // Check first node (should be a literal with value "10" and type i32)
    const parsed_first = parsed.value.arith.first;
    try testing.expectEqual(JsonAstNode.lit, std.meta.activeTag(parsed_first.*));
    try testing.expectEqual(types.TypeName.i32, parsed_first.*.lit.type_name); // Check type_name
    try testing.expectEqualStrings("10", parsed_first.*.lit.val); // Check val

    // Check second node (should be a name with value "x")
    const parsed_second = parsed.value.arith.second;
    try testing.expectEqual(JsonAstNode.nam, std.meta.activeTag(parsed_second.*));
    try testing.expectEqualStrings("x", parsed_second.*.nam);
}

test "parse literals.json" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const json_bytes = try std.fs.cwd().readFileAlloc(allocator, "tests/literals.json", 1024 * 1024); // Limit file size
    defer allocator.free(json_bytes);

    // 2. Parse the JSON into JsonAstNode
    const parsed_node = try json.parseFromSlice(JsonAstNode, allocator, json_bytes, .{ .ignore_unknown_fields = true });
    defer parsed_node.deinit();

    std.debug.print("Parsed item: {}\n", .{parsed_node.value});
}

test "parse let_stmt.json" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const json_bytes = try std.fs.cwd().readFileAlloc(allocator, "tests/simple.json", 1024 * 1024); // Limit file size
    defer allocator.free(json_bytes);

    // 2. Parse the JSON into JsonAstNode
    const parsed_node = try json.parseFromSlice(JsonAstNode, allocator, json_bytes, .{ .ignore_unknown_fields = true });
    defer parsed_node.deinit();

    std.debug.print("Parsed item: {}\n", .{parsed_node.value});
}
