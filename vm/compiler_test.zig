const std = @import("std");
const testing = std.testing;
const json = std.json;
const types = @import("types.zig");
const compile = @import("compiler.zig");

const Value = types.Value;
const UnaryOperator = types.UnaryOperator;
const BinaryOperator = types.BinaryOperator;
const LogicalOperator = types.LogicalOperator;
const Param = types.Param;
const CompileErrors = types.CompileErrors;
const AstNode = types.AstNode;
const Instruction = types.Instruction;
const Compiler = compile.Compiler;

test "serialize AstNode to JSON" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    // Test case 1: Literal node (integer)
    {
        const node = AstNode{
            .Literal = .{ .Int = 42 },
        };

        var string = std.ArrayList(u8).init(allocator);
        defer string.deinit();

        try json.stringify(node, .{}, string.writer());

        const result = string.items;
        try testing.expect(std.mem.indexOf(u8, result, "\"Literal\"") != null);
        try testing.expect(std.mem.indexOf(u8, result, "\"Int\"") != null);
        try testing.expect(std.mem.indexOf(u8, result, "42") != null);
    }

    // Test case 2: Name node
    {
        const name = try allocator.dupe(u8, "testVar");
        const node = AstNode{
            .Name = name,
        };

        var string = std.ArrayList(u8).init(allocator);
        defer string.deinit();

        try json.stringify(node, .{}, string.writer());

        const result = string.items;
        try testing.expect(std.mem.indexOf(u8, result, "\"Name\"") != null);
        try testing.expect(std.mem.indexOf(u8, result, "\"testVar\"") != null);
    }

    // Test case 3: Binary operation node
    {
        const left = try allocator.create(AstNode);
        left.* = AstNode{ .Literal = .{ .Int = 10 } };

        const right = try allocator.create(AstNode);
        right.* = AstNode{ .Literal = .{ .Int = 20 } };

        const node = AstNode{
            .BinaryOp = .{
                .op = .Add,
                .left = left,
                .right = right,
            },
        };

        var string = std.ArrayList(u8).init(allocator);
        defer string.deinit();

        try json.stringify(node, .{}, string.writer());

        const result = string.items;
        std.debug.print("\nSerialized BinaryOp JSON: {s}\n", .{result});
        try testing.expect(std.mem.indexOf(u8, result, "\"BinaryOp\"") != null);
        try testing.expect(std.mem.indexOf(u8, result, "\"op\":\"+\"") != null); // Expect "+" instead of "Add"
        try testing.expect(std.mem.indexOf(u8, result, "\"left\"") != null);
        try testing.expect(std.mem.indexOf(u8, result, "\"right\"") != null);
        try testing.expect(std.mem.indexOf(u8, result, "10") != null);
        try testing.expect(std.mem.indexOf(u8, result, "20") != null);
    }
}

test "parse JSON to AstNode" {
    // var arena = std.heap.ArenaAllocator.init(testing.allocator);
    // defer arena.deinit();
    // const allocator = arena.allocator();

    // Test case 1: Parse a literal node
    {
        const json_str =
            \\{"Literal":{"Int":42}}
        ;

        const item = try json.parseFromSlice(AstNode, testing.allocator, json_str, .{});
        defer item.deinit();
        std.debug.print("Parsed item: {}\n", .{item.value});

        try testing.expectEqual(AstNode.Literal, std.meta.activeTag(item.value));
        try testing.expectEqual(Value.Int, std.meta.activeTag(item.value.Literal));
        try testing.expectEqual(@as(i64, 42), item.value.Literal.Int);
    }

    // Test case 2: Parse a name node
    {
        const json_str =
            \\{ "Name":"testVar"}
        ;

        const item = try json.parseFromSlice(AstNode, testing.allocator, json_str, .{});
        defer item.deinit();
        std.debug.print("Parsed item: {}\n", .{item.value});

        try testing.expectEqual(AstNode.Name, std.meta.activeTag(item.value));
        try testing.expectEqualStrings("testVar", item.value.Name);
    }

    // Test case 3: Parse a binary operation
    {
        const json_str =
            \\{
            \\  "BinaryOp": {
            \\    "op": "+",
            \\    "left": {"Literal":{"Int":10}},
            \\    "right": {"Literal":{"Int":20}}
            \\  }
            \\}
        ;

        const item = try json.parseFromSlice(AstNode, testing.allocator, json_str, .{});
        defer item.deinit();
        std.debug.print("Parsed item: {}\n", .{item.value});

        try testing.expectEqual(AstNode.BinaryOp, std.meta.activeTag(item.value));
        try testing.expectEqual(BinaryOperator.Add, item.value.BinaryOp.op);

        const left = item.value.BinaryOp.left;
        try testing.expectEqual(AstNode.Literal, std.meta.activeTag(left.*));
        try testing.expectEqual(@as(i64, 10), left.*.Literal.Int);

        const right = item.value.BinaryOp.right;
        try testing.expectEqual(AstNode.Literal, std.meta.activeTag(right.*));
        try testing.expectEqual(@as(i64, 20), right.*.Literal.Int);
    }
}

test "round trip AstNode to JSON and back" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    // Create a complex AST node
    const left = try allocator.create(AstNode);
    left.* = AstNode{ .Literal = .{ .Int = 10 } };

    const right = try allocator.create(AstNode);
    const var_name = try allocator.dupe(u8, "x");
    right.* = AstNode{ .Name = var_name };

    const original_node = AstNode{
        .BinaryOp = .{
            .op = .Add,
            .left = left,
            .right = right,
        },
    };

    // Serialize to JSON
    var json_string = std.ArrayList(u8).init(allocator);
    defer json_string.deinit();

    try json.stringify(original_node, .{}, json_string.writer());

    // Print the JSON for debugging
    std.debug.print("Serialized JSON: {s}\n", .{json_string.items});

    // Parse the JSON back to an AstNode
    const parsed = try json.parseFromSlice(AstNode, allocator, json_string.items, .{});
    defer parsed.deinit();

    // Verify the structure is preserved
    try testing.expectEqual(AstNode.BinaryOp, std.meta.activeTag(parsed.value));
    // The parsed value should still be the correct enum member
    try testing.expectEqual(BinaryOperator.Add, parsed.value.BinaryOp.op);

    // Check left node (should be a literal with value 10)
    const parsed_left = parsed.value.BinaryOp.left;
    try testing.expectEqual(AstNode.Literal, std.meta.activeTag(parsed_left.*));
    try testing.expectEqual(Value.Int, std.meta.activeTag(parsed_left.*.Literal));
    try testing.expectEqual(@as(i64, 10), parsed_left.*.Literal.Int);

    // Check right node (should be a name with value "x")
    const parsed_right = parsed.value.BinaryOp.right;
    try testing.expectEqual(AstNode.Name, std.meta.activeTag(parsed_right.*));
    try testing.expectEqualStrings("x", parsed_right.*.Name);
}

test "compile simple program: let x = 1 + 2; x" {
    // Setup
    var compiler = Compiler.init(testing.allocator);
    defer compiler.deinit();

    // Create AST for: let x = 1 + 2; x
    var one = AstNode{ .Literal = .{ .Int = 1 } };
    var two = AstNode{ .Literal = .{ .Int = 2 } };
    var add_expr = AstNode{ .BinaryOp = .{ .op = .Add, .left = &one, .right = &two } };
    var var_decl = AstNode{ .VarDecl = .{ .name = "x", .value = &add_expr } };
    var load_x = AstNode{ .Name = "x" };

    var statements_slice = [_]*AstNode{
        &var_decl,
        &load_x,
    };

    const program = AstNode{ .Sequence = .{ .statements = &statements_slice } };

    // Compile the program
    try compiler.compileProgram(&program);

    // Verify the generated instructions
    const instructions = compiler.instructions.items;

    std.debug.print("Generated Instructions:\n", .{});
    for (compiler.instructions.items, 0..) |instr, i| {
        std.debug.print("{d}: ", .{i});
        switch (instr) {
            .Ld => |name| std.debug.print("Ld(\"{s}\")\n", .{name}),
            .Assign => |name| std.debug.print("Assign(\"{s}\")\n", .{name}),
            // NOTE: Add specific formatting for other instructions if needed
            // e.g., EnterScope, Ldf
            else => std.debug.print("{any}\n", .{instr}),
        }
    }
    try testing.expectEqual(@as(usize, 7), instructions.len);

    // Check specific instructions
    try testing.expectEqual(Instruction{ .Ldc = .{ .Int = 1 } }, instructions[0]);
    try testing.expectEqual(Instruction{ .Ldc = .{ .Int = 2 } }, instructions[1]);
    try testing.expectEqual(Instruction{ .Binop = .Add }, instructions[2]);

    // For string comparisons, we need to check the tag and then the string content
    switch (instructions[3]) {
        .Assign => |name| try testing.expectEqualStrings("x", name),
        else => return error.TestUnexpectedInstructionType,
    }

    switch (instructions[5]) {
        .Ld => |name| try testing.expectEqualStrings("x", name),
        else => return error.TestUnexpectedInstructionType,
    }

    try testing.expectEqual(Instruction.Done, instructions[6]);
}

test "fn_decl_test" {
    // Setup
    var compiler = Compiler.init(testing.allocator);
    defer compiler.deinit();

    var body = AstNode{ .Literal = .{ .Int = 2 } };
    var fn_decl = AstNode{ .FnDecl = .{
        .name = "foo",
        .params = &([_]Param{}),
        .body = &body,
    } };

    var statements_slice = [_]*AstNode{&fn_decl};

    const program = AstNode{ .Sequence = .{ .statements = &statements_slice } };
    // Compile the program
    try compiler.compileProgram(&program);

    // Verify the generated instructions
    try compiler.printCompiledMicrocode();
}

test "logical_test" {
    // Setup
    var compiler = Compiler.init(testing.allocator);
    defer compiler.deinit();

    var left = AstNode{ .Literal = .{ .Bool = true } };
    var right = AstNode{ .Literal = .{ .Bool = false } };
    var log_and = AstNode{ .LogicalOp = .{ .op = .And, .left = &left, .right = &right } };
    var log_or = AstNode{ .LogicalOp = .{ .op = .Or, .left = &left, .right = &right } };

    var statements_slice = [_]*AstNode{
        &log_and,
        &log_or,
    };

    const program = AstNode{ .Sequence = .{ .statements = &statements_slice } };
    // Compile the program
    try compiler.compileProgram(&program);

    // Verify the generated instructions
    try compiler.printCompiledMicrocode();
}
