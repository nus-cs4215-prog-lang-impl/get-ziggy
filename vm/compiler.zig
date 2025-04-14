const std = @import("std");
const Allocator = std.mem.Allocator;
const types = @import("types.zig");

const Value = types.Value;
const UnaryOperator = types.UnaryOperator;
const BinaryOperator = types.BinaryOperator;
const LogicalOperator = types.LogicalOperator;
const Param = types.Param;
const CompileErrors = types.CompileErrors;
const AstNode = types.AstNode;
const Instruction = types.Instruction;
const InstructionData = types.InstructionData;

pub const Compiler = struct {
    alloc: Allocator,
    instructions: std.ArrayList(Instruction),

    pub fn init(alloc: Allocator) Compiler {
        return .{
            .alloc = alloc,
            .instructions = std.ArrayList(Instruction).init(alloc),
        };
    }

    pub fn deinit(self: *Compiler) void {
        // TODO: Need to deallocate strings stored within instructions if they were allocated by the compiler
        self.instructions.deinit();
    }

    fn addInstr(self: *Compiler, instruction_data: InstructionData) !void {
        try self.instructions.append(.{ .data = instruction_data });
    }

    // Helper to get the index of the next instruction to be added
    fn nextInstrAddr(self: *const Compiler) usize {
        return self.instructions.items.len;
    }

    fn scanNodeRecursive(self: *Compiler, node: *const AstNode, locals: *std.ArrayList([]const u8)) !void {
        switch (node.*) {
            .Literal, .Name, .Conditional => {},
            .App => |app_data| {
                try self.scanNodeRecursive(app_data.func, locals);
                for (app_data.args) |arg| try self.scanNodeRecursive(arg, locals);
            },
            .LogicalOp => |log_data| {
                try self.scanNodeRecursive(log_data.left, locals);
                try self.scanNodeRecursive(log_data.right, locals);
            },
            .BinaryOp => |bin_data| {
                try self.scanNodeRecursive(bin_data.left, locals);
                try self.scanNodeRecursive(bin_data.right, locals);
            },
            .UnaryOp => |un_data| try self.scanNodeRecursive(un_data.operand, locals),
            .Lambda => {}, // Don't recurse into nested functions/lambdas for *this* scope's locals
            .Sequence => |seq_data| {
                for (seq_data.statements) |stmt| try self.scanNodeRecursive(stmt, locals);
            },
            .Block => |block_data| try self.scanNodeRecursive(block_data.body, locals),
            .VarDecl => |decl_data| try locals.append(decl_data.name),
            .Assignment => |assign_data| try self.scanNodeRecursive(assign_data.value, locals),
            .FnDecl => |fn_data| try locals.append(fn_data.name), // Function name is local
            .Return => |ret_data| if (ret_data.value) |v| try self.scanNodeRecursive(v, locals),
            .WhileLoop => |loop_data| try self.scanNodeRecursive(loop_data.body, locals),
        }
    }

    fn scanForLocals(self: *Compiler, node: *const AstNode) ![][]const u8 {
        var locals = std.ArrayList([]const u8).init(self.alloc);
        errdefer locals.deinit();

        try self.scanNodeRecursive(node, &locals);

        return locals.toOwnedSlice();
    }

    // Helper to patch a jump instruction later
    fn patchJump(self: *Compiler, instr_index: usize, target_addr: usize) void {
        switch (self.instructions.items[instr_index].data) {
            .Jof => |*addr| addr.* = target_addr,
            .Goto => |*addr| addr.* = target_addr,
            .JDF => |*addr| addr.* = target_addr,
            else => @panic("Attempting to patch non-jump instruction"),
        }
    }

    fn compileBinaryOp(self: *Compiler, left: *const AstNode, right: *const AstNode, op: BinaryOperator) CompileErrors!void {
        try self.compile(left);
        try self.compile(right);
        try self.addInstr(.{ .Binop = op });
    }

    fn compileUnaryOp(self: *Compiler, operand: *const AstNode, op: UnaryOperator) CompileErrors!void {
        try self.compile(operand);
        try self.addInstr(.{ .Unop = op });
    }

    fn compileSequence(self: *Compiler, statements: []*AstNode) CompileErrors!void {
        // WARNING: Should this do nothing?
        if (statements.len == 0) {
            return;
        }

        var i: usize = 0;
        while (i < statements.len) : (i += 1) {
            try self.compile(statements[i]);
            // NOTE: Pop result unless it's the last statement. For this to work, only this
            // compileSequence function should be responsible for popping the statements value
            if (i < statements.len - 1) {
                try self.addInstr(.Pop);
            }
        }
    }

    fn compileBlock(self: *Compiler, body: *const AstNode) CompileErrors!void {
        const locals = try self.scanForLocals(body);
        try self.addInstr(.{ .EnterScope = .{ .locals = locals } });
        try self.compile(body);
        try self.addInstr(.ExitScope);
    }

    // NOTE: Variable Declaration should NOT leave a value on the stack, it is considered a statement
    // and returns nothing. This pop behaviour should be managed by compileSequence, not here.
    fn compileVarDecl(self: *Compiler, name: []const u8, value: *const AstNode) CompileErrors!void {
        try self.compile(value);
        try self.addInstr(.{ .Assign = name });
    }

    // NOTE: See compileVarDecl on popping the value
    fn compileAssignment(self: *Compiler, name: []const u8, value: *const AstNode) CompileErrors!void {
        try self.compile(value);
        try self.addInstr(.{ .Assign = name });
    }

    // NOTE: CompileErrors!void is a hack to get around "unable to resolve inferred error set":
    // https://github.com/ziglang/zig/issues/763
    // TODO: When all cases are implemented, we should not need CompileErrors anymore?
    pub fn compile(self: *Compiler, node: *const AstNode) CompileErrors!void {
        switch (node.*) {
            .Literal => |val| try self.addInstr(.{ .Ldc = val }),
            .Name => |name| try self.addInstr(.{ .Ld = name }),
            .BinaryOp => |op_data| try self.compileBinaryOp(op_data.left, op_data.right, op_data.op),
            .UnaryOp => |op_data| try self.compileUnaryOp(op_data.operand, op_data.op),
            .Sequence => |seq_data| try self.compileSequence(seq_data.statements),
            .Block => |block_data| try self.compileBlock(block_data.body),
            .VarDecl => |decl_data| try self.compileVarDecl(decl_data.name, decl_data.value),
            .Assignment => |assign_data| try self.compileAssignment(assign_data.name, assign_data.value),

            // --- More Complex Cases (GPT Placeholders) ---

            .App => |app_data| {
                try self.compile(app_data.func);
                for (app_data.args) |arg| {
                    try self.compile(arg);
                }
                _ = try self.addInstr(.{ .Call = .{ .arity = app_data.args.len } });
            },

            .Conditional => |cond_data| {
                // 1. Compile condition
                try self.compile(cond_data.condition);

                // 2. Add Jof (Jump if False) instruction, store its index
                const jof_idx = self.nextInstrAddr();
                try self.addInstr(.{ .Jof = 0 }); // Placeholder address 0
                // 3. Compile 'then' branch (cons)
                try self.compile(cond_data.cons);
                // 4. Add Goto instruction (to jump over 'else'), store its index
                const goto_idx = self.nextInstrAddr();
                try self.addInstr(.{ .Goto = 0 }); // Placeholder address 0

                // 5. Get address for start of 'else' branch (alt)
                const alt_addr = self.nextInstrAddr();
                // 6. Compile 'else' branch (alt)
                try self.compile(cond_data.alt);
                // 7. Get address after 'else' branch
                const end_addr = self.nextInstrAddr();

                // 8. Patch Goto to jump to end_addr
                self.patchJump(goto_idx, end_addr);
                // 9. Patch Jof to jump to alt_addr
                self.patchJump(jof_idx, alt_addr);
            },

            .Lambda => |lambda_data| {
                // Compiling functions/lambdas requires careful handling of scope and jumps.
                // Technique: Jump over the body, compile body, then load function object.
                // 1. Add Goto to jump over the function body, store index
                const goto_idx = self.nextInstrAddr();
                try self.addInstr(.{ .Goto = 0 }); // Placeholder
                // 2. Get the start address of the function body
                const func_body_addr = self.nextInstrAddr();
                // 3. Compile the function body
                //    Need EnterScope for params + body locals, then ExitScope? Or handled by Call/Reset?
                //    Let's assume Call handles scope setup based on Ldf params.
                try self.compile(lambda_data.body);
                // 4. Add Reset instruction at the end of the body to return
                try self.addInstr(.Reset);
                // 5. Get address after the function body
                const after_func_addr = self.nextInstrAddr();
                // 6. Patch the initial Goto to jump to after_func_addr
                self.patchJump(goto_idx, after_func_addr);
                // 7. Add the Ldf instruction *before* the jump (tricky, need to insert or plan ahead)
                //    Alternative: Add Ldf *now*, pointing to func_body_addr. This is simpler.
                try self.addInstr(.{ .Ldf = .{ .params = lambda_data.params, .addr = func_body_addr } });
                // This puts the function object on the stack *after* the jump over its code.
            },

            .FnDecl => |fndecl_data| {
                var fun = AstNode{ .Lambda = .{ .params = fndecl_data.params, .body = fndecl_data.body } };
                var assign = AstNode{ .Assignment = .{ .name = fndecl_data.name, .value = &fun } };
                try self.compile(&assign);
            },

            .Return => |ret_data| {
                if (ret_data.value) |val_node| {
                    // Compile the return value if present
                    try self.compile(val_node);
                } else {
                    // No return value specified, push Undefined?
                    //_ = try self.addInstr(.{ .Ldc = .{ .Undefined = .{} } });
                }
                // Add Reset instruction to return from function
                _ = try self.addInstr(.Reset);
            },

            // .LogicalOp => |log_op_data| {
            //     // Logical operators require short-circuiting via jumps.
            //     switch (log_op_data.op) {
            //         .And => {
            //             // 1. Compile left
            //             try self.compile(log_op_data.left);
            //             // 2. Add Jof (if left is false, result is false, jump to end)
            //             const jof_idx = try self.addInstr(.{ .Jof = 0 });
            //             // 3. Left was true, result is the right side. Pop the true value from left.
            //             _ = try self.addInstr(.Pop);
            //             // 4. Compile right
            //             try self.compile(log_op_data.right);
            //             // 5. Get end address
            //             const end_addr = self.nextInstrAddr();
            //             // 6. Patch Jof
            //             self.patchJump(jof_idx, end_addr);
            //             // Stack now has: result of right (if left was true), or false (if left was false)
            //         },
            //         .Or => {
            //             // 1. Compile left
            //             try self.compile(log_op_data.left);
            //             // 2. Add Jof (if left is false, jump to compile right)
            //             const jof_idx = try self.addInstr(.{ .Jof = 0 });
            //             // 3. Left was true. Result is true. Jump to end.
            //             const goto_idx = try self.addInstr(.{ .Goto = 0 });
            //             // 4. Get address for right side compilation
            //             const right_addr = self.nextInstrAddr();
            //             // 5. Patch Jof to jump here
            //             self.patchJump(jof_idx, right_addr);
            //             // 6. Left was false. Pop the false value.
            //             _ = try self.addInstr(.Pop);
            //             // 7. Compile right
            //             try self.compile(log_op_data.right);
            //             // 8. Get end address
            //             const end_addr = self.nextInstrAddr();
            //             // 9. Patch Goto to jump here
            //             self.patchJump(goto_idx, end_addr);
            //             // Stack now has: true (if left was true), or result of right (if left was false)
            //         },
            //     }
            // },

            .WhileLoop => |loop_data| {
                // 1. Get address for condition check (loop start)
                const cond_addr = self.nextInstrAddr();
                // 2. Compile condition
                try self.compile(loop_data.condition);
                // 3. Add Jof to jump past the loop body if condition is false
                const jof_idx = self.nextInstrAddr();
                try self.addInstr(.{ .Jof = 0 });
                // 4. Compile loop body
                try self.compile(loop_data.body);
                // 5. Pop the result of the body (loop body result usually discarded)
                try self.addInstr(.Pop);
                // 6. Add Goto to jump back to the condition check
                try self.addInstr(.{ .Goto = cond_addr });
                // 7. Get address after the loop
                const after_loop_addr = self.nextInstrAddr();
                // 8. Patch Jof to jump here
                self.patchJump(jof_idx, after_loop_addr);
            },

            // TODO: Remove this
            else => {
                // Get the tag name for better error reporting
                const tag_name = @tagName(node.*);
                std.debug.print("Compilation error: Unimplemented AST node type: {s}\n", .{tag_name});
                return CompileErrors.UnimplementedAstNode;
            },
        }
    }

    pub fn compileProgram(self: *Compiler, program_node: *const AstNode) !void {
        // TODO: Could add setup here if needed (e.g., initial EnterScope for globals)
        try self.compile(program_node);
        _ = try self.addInstr(.Done);
    }

    pub fn printCompiledMicrocode(self: *Compiler) !void {
        const instructions = self.instructions.items;

        std.debug.print("Generated Instructions:\n", .{});
        for (instructions, 0..) |instr, i| {
            std.debug.print("{d}: ", .{i});
            switch (instr.data) {
                .Ldc => |val| std.debug.print("Ldc({any})\n", .{val}),
                .Ld => |name| std.debug.print("Ld(\"{s}\")\n", .{name}),
                .Assign => |name| std.debug.print("Assign(\"{s}\")\n", .{name}),
                .Unop => |op| std.debug.print("Unop({any})\n", .{op}),
                .Binop => |op| std.debug.print("Binop({any})\n", .{op}),
                .Pop => std.debug.print("Pop\n", .{}),
                .Jof => |addr| std.debug.print("Jof({d})\n", .{addr}),
                .Goto => |addr| std.debug.print("Goto({d})\n", .{addr}),
                .EnterScope => |scope| {
                    std.debug.print("EnterScope([", .{});
                    for (scope.locals, 0..) |local, j| {
                        if (j > 0) std.debug.print(", ", .{});
                        std.debug.print("\"{s}\"", .{local});
                    }
                    std.debug.print("])\n", .{});
                },
                .ExitScope => std.debug.print("ExitScope\n", .{}),
                .Ldf => |f| {
                    std.debug.print("Ldf(params: [", .{});
                    for (f.params, 0..) |param, j| {
                        if (j > 0) std.debug.print(", ", .{});
                        std.debug.print("{any}", .{param});
                    }
                    std.debug.print("], addr: {d})\n", .{f.addr});
                },
                .Call => |c| std.debug.print("Call(arity: {d})\n", .{c.arity}),
                .TailCall => |tc| std.debug.print("TailCall(arity: {d})\n", .{tc.arity}),
                .Reset => std.debug.print("Reset\n", .{}),
                .Done => std.debug.print("Done\n", .{}),
            }
        }
    }
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var compiler = Compiler.init(allocator);
    defer compiler.deinit();

    // Example AST: let x = 1 + 2; x
    // Node definitions (usually built by a parser)
    // These can remain const because we take *const pointers below
    var one = AstNode{ .Literal = .{ .Int = 1 } };
    var two = AstNode{ .Literal = .{ .Int = 2 } };
    // The struct fields now expect *const AstNode, so &one and &two work correctly
    var add_expr = AstNode{ .BinaryOp = .{ .op = .Add, .left = &one, .right = &two } };
    var var_decl = AstNode{ .VarDecl = .{ .name = "x", .value = &add_expr } };
    var load_x = AstNode{ .Name = "x" };

    // Sequence of statements - type changed to []*const AstNode
    var statements_slice = [_]*AstNode{
        &var_decl,
        &load_x,
    };
    // Need to allocate on heap if we want to pass a slice owned by the allocator
    // Or just use the stack-allocated slice directly for this example
    // var statements = try allocator.alloc(*const AstNode, 2);
    // defer allocator.free(statements);
    // statements[0] = &var_decl;
    // statements[1] = &load_x;

    const program = AstNode{ .Sequence = .{ .statements = &statements_slice } };

    std.debug.print("Compiling program: let x = 1 + 2; x\n", .{});
    try compiler.compileProgram(&program);

    std.debug.print("Generated Instructions:\n", .{});
    for (compiler.instructions.items, 0..) |instr, i| {
        std.debug.print("{d}: ", .{i});
        switch (instr.data) {
            .Ld => |name| std.debug.print("Ld(\"{s}\")\n", .{name}),
            .Assign => |name| std.debug.print("Assign(\"{s}\")\n", .{name}),
            // NOTE: Add specific formatting for other instructions if needed
            // e.g., EnterScope, Ldf
            else => std.debug.print("{any}\n", .{instr.data}),
        }
    }
}
