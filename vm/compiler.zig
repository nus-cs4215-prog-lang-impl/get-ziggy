const std = @import("std");
const Allocator = std.mem.Allocator;
const types = @import("types.zig");

const LiteralVal = types.LiteralVal; // Use LiteralVal
const TypeName = types.TypeName; // Import TypeName
const UnaryOperator = types.UnaryOperator;
const BinaryOperator = types.BinaryOperator;
const LogicalOperator = types.LogicalOperator;
const Param = types.Param;
const CompileErrors = types.CompileErrors;
// const AstNode = types.AstNode; // Removed
const JsonAstNode = types.JsonAstNode;
const Instruction = types.Instruction;

pub const Compiler = struct {
    alloc: Allocator,
    instructions: std.ArrayList(Instruction),
    compiletime_env: ?[][]u32,

    pub fn init(alloc: Allocator) Compiler {
        return .{
            .alloc = alloc,
            .instructions = std.ArrayList(Instruction).init(alloc),
            .compiletime_env = null,
        };
    }

    pub fn deinit(self: *Compiler) void {
        // Deallocate strings stored within instructions if they were allocated by the compiler
        for (self.instructions.items) |instr| {
            switch (instr) {
                .Ld => |name| self.alloc.free(name),
                .Assign => |name| self.alloc.free(name),
                .EnterScope => |scope| {
                    for (scope.locals) |local| self.alloc.free(local);
                    self.alloc.free(scope.locals); // Free the outer slice too
                },
                // Deallocate LiteralVal string if needed (assuming it might be duped)
                // TODO: Confirm if LiteralVal.val needs freeing. Assuming yes for now if duped.
                .Ldc => |lit| self.alloc.free(lit.val),
                //.Ldf => |f| {
                //    // Assuming Param names are also allocated strings that need freeing
                //    // If Param names point to original AST strings, this is not needed.
                //    // For now, let's assume they might be owned by the instruction.
                //    // TODO: Clarify ownership of Param names. If they are slices of
                //    // the original source or AST, they don't need freeing here.
                //    // If they are copied/allocated specifically for the instruction, they do.
                //    // Let's comment this out for now, assuming they are not owned here.
                //    // for (f.params) |param| self.alloc.free(param.name);
                //    // self.alloc.free(f.params); // Free the slice of params
                //},
                else => {}, // Other instructions don't own allocated strings currently
            }
        }
        self.instructions.deinit();
    }

    fn addInstr(self: *Compiler, instruction: Instruction) !void {
        // Handle potential allocation for string-based instructions
        var owned_instruction = instruction;
        switch (instruction) {
            .Ld => |name| owned_instruction = .{ .Ld = try self.alloc.dupe(u8, name) },
            .Assign => |name| owned_instruction = .{ .Assign = try self.alloc.dupe(u8, name) },
            // Also dupe the string inside LiteralVal for Ldc
            .Ldc => |lit| owned_instruction = .{ .Ldc = .{ .val = try self.alloc.dupe(u8, lit.val), .type_name = lit.type_name } },
            // TODO: Handle EnterScope and Ldf if their strings need allocation/duplication
            // This depends on whether the input AST strings are guaranteed to live long enough.
            // For now, assume they do, but duplication might be safer.
            else => {},
        }
        try self.instructions.append(owned_instruction);
    }

    // Helper to get the index of the next instruction to be added
    fn nextInstrAddr(self: *const Compiler) usize {
        return self.instructions.items.len;
    }

    // Scan for locals defined within a given node (scope)
    fn scanNodeRecursive(self: *Compiler, node: *const JsonAstNode, locals: *std.ArrayList([]const u8)) !void {
        switch (node.*) {
            .lit, .nam, .continue_statement, .break_statement => {}, // Literals and names don't declare locals
            .app => |app_data| {
                // Scan function/name part (might be complex expr) and args
                // try self.scanNodeRecursive(app_data.nam, locals); // 'nam' is string, not node
                for (app_data.args) |arg| try self.scanNodeRecursive(arg, locals);
            },
            .logic => |op_data| {
                try self.scanNodeRecursive(op_data.first, locals);
                try self.scanNodeRecursive(op_data.second, locals);
            },
            .arith, .comp, .reassign, .compound_assign, .type_cast => |op_data| {
                try self.scanNodeRecursive(op_data.first, locals);
                try self.scanNodeRecursive(op_data.second, locals);
            },
            .borrow, .borrow_mut, .deref, .neg, .question => |op_data| {
                try self.scanNodeRecursive(op_data.first, locals);
            },
            .seq => |seq_data| {
                for (seq_data.stmts) |stmt| try self.scanNodeRecursive(stmt, locals);
            },
            .blk => |blk_data| {
                // Blocks introduce scope, but scanning happens *within* the block's content
                try self.scanNodeRecursive(blk_data.body, locals);
            },
            .assign => |assign_data| {
                // This is a variable declaration (let binding) - add its name
                try locals.append(assign_data.nam);
                // Also scan the value expression for nested declarations (though less common)
                try self.scanNodeRecursive(assign_data.val, locals);
            },
            .cond => |cond_data| {
                try self.scanNodeRecursive(cond_data.pred, locals);
                try self.scanNodeRecursive(cond_data.cons, locals);
                if (cond_data.alt) |alt_node| {
                    try self.scanNodeRecursive(alt_node, locals);
                }
            },
            .fun => |fun_data| {
                // Function declaration introduces the function name as a local
                try locals.append(fun_data.nam);
                // Don't recurse into the body for *this* scope's locals
                // If body exists, scan it for its own locals if needed elsewhere, but not here.
                if (fun_data.body) |body_node| {
                    _ = body_node; // Avoid unused variable warning if not scanning here
                }
            },
            .while_loop => |loop_data| {
                try self.scanNodeRecursive(loop_data.pred, locals);
                try self.scanNodeRecursive(loop_data.body, locals);
            },
            .return_statement => |ret_data| {
                if (ret_data.body) |body_node| {
                    try self.scanNodeRecursive(body_node, locals);
                }
            },
        }
    }

    // Scan the direct children of a node (typically a block or sequence) for locals.
    // Does not recurse deeply into expressions unless necessary (like nested blocks).
    fn scanForLocals(self: *Compiler, node: *const JsonAstNode) ![][]const u8 {
        var localsList = std.ArrayList([]const u8).init(self.alloc);
        errdefer localsList.deinit(); // Ensure cleanup on error

        switch (node.*) {
            // Only Blocks and Sequences directly contain lists of statements
            // where top-level declarations are expected.
            .blk => |blk_data| try self.scanNodeRecursive(blk_data.body, &localsList),
            .seq => |seq_data| {
                for (seq_data.stmts) |stmt| {
                    // Only look for direct declarations (`assign` or `fun`) within the sequence
                    switch (stmt.*) {
                        .assign => |assign_data| try localsList.append(assign_data.nam),
                        .fun => |fun_data| try localsList.append(fun_data.nam),
                        // TODO: Consider if other statement types might declare locals directly?
                        // e.g., `for` loops might declare loop variables.
                        else => {},
                    }
                }
            },
            // Other node types don't directly contain declarable locals in the same way.
            // If a function body needs scanning, it should be handled when compiling the function.
            else => {},
        }

        // Duplicate the strings to ensure they are owned by the EnterScope instruction
        var ownedLocals = try self.alloc.alloc([]const u8, localsList.items.len);
        errdefer self.alloc.free(ownedLocals);

        for (localsList.items, 0..) |local, i| {
            ownedLocals[i] = try self.alloc.dupe(u8, local);
        }

        localsList.deinit(); // Deinit the temporary list
        return ownedLocals;
    }

    // Helper to patch a jump instruction later
    fn patchJump(self: *Compiler, instr_index: usize, target_addr: usize) void {
        // Ensure the instruction exists before trying to patch
        if (instr_index >= self.instructions.items.len) {
            @panic("Attempting to patch out-of-bounds instruction index");
        }
        switch (self.instructions.items[instr_index]) {
            .Jof => |*addr| addr.* = target_addr,
            .Goto => |*addr| addr.* = target_addr,
            else => @panic("Attempting to patch non-jump instruction"),
        }
    }

    fn compileBinaryOp(self: *Compiler, first: *const JsonAstNode, second: *const JsonAstNode, op: BinaryOperator) CompileErrors!void {
        try self.compile(first);
        try self.compile(second);
        try self.addInstr(.{ .Binop = op });
    }

    fn compileUnaryOp(self: *Compiler, first: *const JsonAstNode, op: UnaryOperator) CompileErrors!void {
        try self.compile(first);
        try self.addInstr(.{ .Unop = op });
    }

    fn compileSequence(self: *Compiler, statements: []*JsonAstNode) CompileErrors!void {
        if (statements.len == 0) {
            // An empty sequence should perhaps leave 'undefined' or equivalent?
            // For now, let's treat it as doing nothing, stack remains unchanged.
            // If the sequence is the *last* thing in a block/program,
            // the lack of a value might be handled by the caller context.
            // Let's push Undefined here explicitly for empty sequence.
            try self.addInstr(.{ .Ldc = .{ .val = "undefined", .type_name = .Undefined } });
            return;
        }

        var i: usize = 0;
        while (i < statements.len) : (i += 1) {
            try self.compile(statements[i]);
            // Pop result unless it's the last statement in the sequence.
            // The last statement's value becomes the value of the sequence.
            if (i < statements.len - 1) {
                try self.addInstr(.Pop);
            }
        }
    }

    fn compileBlock(self: *Compiler, body: *const JsonAstNode) CompileErrors!void {
        const locals = try self.scanForLocals(body);
        // Only add scope instructions if there are locals declared
        const has_locals = locals.len > 0;

        if (has_locals) {
            try self.addInstr(.{ .EnterScope = .{ .locals = locals } });
        }

        try self.compile(body); // Compile the block's content

        if (has_locals) {
            try self.addInstr(.ExitScope);
        }
        // Note: The value of the block is the value of its last expression/statement,
        // which is left on the stack by the recursive call to compile(body).
    }

    // Compiles variable declaration (`let name = value;`)
    // This is treated as a statement and should not leave a value on the stack itself.
    fn compileVarDecl(self: *Compiler, name: []const u8, value: *const JsonAstNode) CompileErrors!void {
        try self.compile(value); // Compile the value expression first
        try self.addInstr(.{ .Assign = name }); // Assign the computed value to the name
        // The result of the assignment itself is not kept on the stack.
        // If this is part of a sequence, compileSequence will handle popping.
    }

    // Compiles reassignment (`name = value;`)
    fn compileReassignment(self: *Compiler, name: []const u8, value: *const JsonAstNode) CompileErrors!void {
        // In JsonAstNode, reassignment is represented via BinaryOperation with AssignOperator
        // This function might not be directly called if handled by compileBinaryOp.
        // However, if called directly from a specific AST node type for reassignment:
        try self.compile(value);
        try self.addInstr(.{ .Assign = name }); // Use Assign instruction for reassignment too
    }

    fn compileConditional(self: *Compiler, condition: *const JsonAstNode, cons: *const JsonAstNode, alt: ?*const JsonAstNode) CompileErrors!void {
        // 1. Compile condition
        try self.compile(condition);

        // 2. Add Jof (Jump if False) instruction, store its index
        const jof_idx = self.nextInstrAddr();
        try self.addInstr(.{ .Jof = 0 }); // Placeholder address 0

        // 3. Compile 'then' branch (cons)
        try self.compile(cons);
        // If the 'then' branch executed, we need to jump over the 'else' branch.
        // 4. Add Goto instruction (to jump over 'else'), store its index
        const goto_idx = self.nextInstrAddr();
        try self.addInstr(.{ .Goto = 0 }); // Placeholder address 0

        // 5. Get address for start of 'else' branch (alt) - this is where Jof jumps to
        const alt_addr = self.nextInstrAddr();
        // 6. Patch Jof to jump to alt_addr
        self.patchJump(jof_idx, alt_addr);

        // 7. Compile 'else' branch (alt)
        // TODO: Can we just remove else branch altogehter if empty?
        if (alt) |alt_node| {
            try self.compile(alt_node);
        } else {
            // If there's no 'else' branch, we can push 'undefined' or equivalent.
            // This is the default value for the 'else' case.
            try self.addInstr(.{ .Ldc = .{ .val = "undefined", .type_name = .Undefined } });
        }
        // 8. Get address after 'else' branch - this is where Goto jumps to
        const end_addr = self.nextInstrAddr();
        // 9. Patch Goto to jump to end_addr
        self.patchJump(goto_idx, end_addr);
        // The result of the conditional (either from 'cons' or 'alt') remains on the stack.
    }

    // Compiles a function definition (declaration).
    // This involves creating a closure object (Ldf) and assigning it to the function's name.
    fn compileFnDecl(self: *Compiler, name: []const u8, params: []Param, body: ?*JsonAstNode) CompileErrors!void {
        // Technique: Define the function object first, then assign it.
        // 1. Add Goto to jump over the function body compilation step
        const goto_over_body_idx = self.nextInstrAddr();
        try self.addInstr(.{ .Goto = 0 }); // Placeholder

        // 2. Get the start address of the actual function code
        const func_body_addr = self.nextInstrAddr();

        // 3. Compile the function body itself, if it exists.
        if (body) |body_node| {
            // A function body should implicitly act like a block, managing its own scope.
            // We might need to ensure EnterScope/ExitScope are handled correctly for parameters and locals.
            // Let's assume compileBlock or equivalent logic handles the scope within the body.
            // TODO: Refine scope handling for function bodies.
            // For now, just compile the body node.
            // const body_locals = try self.scanForLocals(body_node); // Scan locals *within* the body
            // Need to include params in the scope? The VM's CALL instruction should handle this.
            // try self.addInstr(.{ .EnterScope = .{ .locals = body_locals }}); // Enter scope for body locals
            try self.compile(body_node);
            // try self.addInstr(.ExitScope); // Exit scope for body locals
        } else {
            // If there's no body, the function should implicitly return 'undefined' or equivalent.
            // Push Undefined here.
            try self.addInstr(.{ .Ldc = .{ .val = "undefined", .type_name = .Undefined } });
        }

        // 4. Add Reset instruction at the end of the body to return control.
        try self.addInstr(.Reset);

        // 5. Get address after the function body code. This is where the initial Goto jumps to.
        const after_func_body_addr = self.nextInstrAddr();
        // 6. Patch the initial Goto to jump here.
        self.patchJump(goto_over_body_idx, after_func_body_addr);

        // 7. Now, add the Ldf instruction. This creates the function object.
        //    It needs the parameter list and the address where the function code starts.
        //    TODO: Decide if params need deep copy or if slice is okay. Assume slice for now.
        //    Need to allocate params if they aren't guaranteed to live?
        //    Let's assume the Param slice comes from the AST and lives long enough.
        try self.addInstr(.{ .Ldf = .{ .params = params, .addr = func_body_addr } });

        // 8. Assign the created function object (now on the stack) to the function name.
        try self.addInstr(.{ .Assign = name });

        // 9. Function declaration is a statement; its "value" (the function object)
        //    is assigned, but the statement itself doesn't leave a value on the stack.
        //    If part of a sequence, compileSequence will pop this.
    }

    fn get_compiletime_env_pos(self: *Compiler, name: []u8) [2]u32 {
        _ = self;
        _ = name;
        return .{ 420, 420 };
    }

    // NOTE: CompileErrors!void is a hack to get around "unable to resolve inferred error set":
    // https://github.com/ziglang/zig/issues/763
    // TODO: When all cases are implemented, we should not need CompileErrors anymore?
    pub fn compile(self: *Compiler, node: *const JsonAstNode) CompileErrors!void {
        switch (node.*) {
            // Use lit_data directly for Ldc
            .lit => |lit_data| try self.addInstr(.{ .Ldc = lit_data }),
            .nam => |name| try self.addInstr(.{ .Ld = .{ .nam = name, .pos = self.get_compiletime_env_pos(name) } }),

            // Binary Operations
            .comp => |op_data| try self.compileBinaryOp(op_data.first, op_data.second, op_data.sym),
            .arith => |op_data| try self.compileBinaryOp(op_data.first, op_data.second, op_data.sym),
            .reassign => |op_data| {
                try self.compile(op_data.second); // Compile the value first
                // Assuming op_data.first is a .nam node for reassignment target
                // TODO: Handle more complex assignment targets (e.g., struct fields) if needed
                if (op_data.first.* == .nam) {
                    try self.addInstr(.{ .Assign = op_data.first.nam });
                } else {
                    std.debug.print("Compilation error: Invalid reassignment target\n", .{});
                    return CompileErrors.UnimplementedAstNode; // Or a more specific error
                }
            },
            .compound_assign => |op_data| {
                // e.g., x += 5 translates to: Ld x, Ldc 5, Binop Add, Assign x
                // Assuming op_data.first is a .nam node for assignment target
                if (op_data.first.* == .nam) {
                    const name = op_data.first.nam;
                    try self.addInstr(.{ .Ld = .{ .name = name, .pos = self.get_compiletime_env_pos(name) } }); // Load current value
                    try self.compile(op_data.second); // Compile the right-hand side value
                    // Convert compound operator to the corresponding basic binary operator
                    const basic_op = switch (op_data.sym.compound_assign) {
                        .AddAssign => BinaryOperator{ .arith = .Add },
                        .SubAssign => BinaryOperator{ .arith = .Sub },
                        .MulAssign => BinaryOperator{ .arith = .Mul },
                        .DivAssign => BinaryOperator{ .arith = .Div },
                        .ModAssign => BinaryOperator{ .arith = .Mod },
                        .BitAndAssign => BinaryOperator{ .arith = .Bitand },
                        .BitOrAssign => BinaryOperator{ .arith = .Bitor },
                        .BitXorAssign => BinaryOperator{ .arith = .Bitxor },
                        .ShlAssign => BinaryOperator{ .arith = .Shl },
                        .ShrAssign => BinaryOperator{ .arith = .Shr },
                    };
                    try self.addInstr(.{ .Binop = basic_op }); // Perform the operation
                    try self.addInstr(.{ .Assign = name }); // Assign the result back
                } else {
                    std.debug.print("Compilation error: Invalid compound assignment target\n", .{});
                    return CompileErrors.UnimplementedAstNode; // Or a more specific error
                }
            },
            .type_cast => |op_data| {
                // Compile the expression being casted
                try self.compile(op_data.first);
                // The 'second' part should represent the type, but instructions don't handle types yet.
                // For now, we might ignore the type cast or add a specific instruction if needed.
                // Let's assume type cast is handled by Binop instruction for now.
                // TODO: Implement proper type casting instruction/logic if required by VM.
                // This might involve adding the type info to the instruction.
                try self.addInstr(.{ .Binop = op_data.sym });
            },

            // Unary Operations
            .borrow => |op_data| try self.compileUnaryOp(op_data.first, op_data.sym),
            .borrow_mut => |op_data| try self.compileUnaryOp(op_data.first, op_data.sym),
            .deref => |op_data| try self.compileUnaryOp(op_data.first, op_data.sym),
            .neg => |op_data| try self.compileUnaryOp(op_data.first, op_data.sym),
            .question => |op_data| try self.compileUnaryOp(op_data.first, op_data.sym),

            .seq => |seq_data| try self.compileSequence(seq_data.stmts),
            .blk => |blk_data| try self.compileBlock(blk_data.body),

            // Variable Declaration (let binding)
            .assign => |assign_data| try self.compileVarDecl(assign_data.nam, assign_data.val),

            // Control Flow & Functions
            .app => |app_data| {
                // Need to compile the function expression first, then args
                // Assuming app_data.nam is the function name for now.
                // TODO: Handle cases where the function is a complex expression.
                try self.addInstr(.{ .Ld = .{ .nam = app_data.nam, .pos = self.get_compiletime_env_pos(app_data.nam) } }); // Load function by name

                // Compile arguments
                for (app_data.args) |arg| {
                    try self.compile(arg);
                }
                // Add Call instruction
                try self.addInstr(.{ .Call = .{ .arity = app_data.args.len } });
            },

            .cond => |cond_data| {
                try self.compileConditional(cond_data.pred, cond_data.cons, cond_data.alt);
            },

            .fun => |fndecl_data| {
                // Function declaration compiles to Ldf + Assign
                try self.compileFnDecl(fndecl_data.nam, fndecl_data.params, fndecl_data.body);
            },

            .return_statement => |ret_data| {
                // Compile the return value expression
                if (ret_data.body) |body_node| {
                    try self.compile(body_node);
                } else {
                    // If there's no return value, we might want to push 'undefined' or equivalent.
                    // This is the default return value for functions without explicit return.
                    try self.addInstr(.{ .Ldc = .{ .val = "undefined", .type_name = .Undefined } });
                }
                try self.addInstr(.Reset);
            },

            .logic => |log_op_data| {
                // Logical operators require short-circuiting via jumps.
                switch (log_op_data.sym.logic) {
                    .And => {
                        // 1. Compile left
                        try self.compile(log_op_data.first);
                        // 2. Add Jof (if left is false, result is false, jump to end)
                        const jof_idx = self.nextInstrAddr();
                        try self.addInstr(.{ .Jof = 0 }); // Placeholder
                        // 3. Left was true. Pop the true value. Result is the right side.
                        try self.addInstr(.Pop);
                        // 4. Compile right
                        try self.compile(log_op_data.second);
                        // 5. Get end address (address after right side is compiled)
                        const end_addr = self.nextInstrAddr();
                        // 6. Patch Jof to jump to end_addr
                        self.patchJump(jof_idx, end_addr);
                        // Stack now has: result of right (if left was true), or false (if left was false and jumped)
                    },
                    .Or => {
                        // 1. Compile left
                        try self.compile(log_op_data.first);
                        // 2. Add Jof (if left is false, jump to compile right)
                        const jof_idx = self.nextInstrAddr();
                        try self.addInstr(.{ .Jof = 0 }); // Placeholder
                        // 3. Left was true. Result is true. Jump *past* the right side compilation.
                        const goto_idx = self.nextInstrAddr();
                        try self.addInstr(.{ .Goto = 0 }); // Placeholder
                        // 4. Get address for right side compilation (where Jof jumps)
                        const right_addr = self.nextInstrAddr();
                        // 5. Patch Jof to jump here
                        self.patchJump(jof_idx, right_addr);
                        // 6. Left was false. Pop the false value.
                        try self.addInstr(.Pop);
                        // 7. Compile right
                        try self.compile(log_op_data.second);
                        // 8. Get end address (where Goto jumps)
                        const end_addr = self.nextInstrAddr();
                        // 9. Patch Goto to jump here
                        self.patchJump(goto_idx, end_addr);
                        // Stack now has: true (if left was true and jumped), or result of right (if left was false)
                    },
                }
            },

            .while_loop => |loop_data| {
                // 1. Get address for condition check (loop start)
                const cond_addr = self.nextInstrAddr();
                // 2. Compile condition
                try self.compile(loop_data.pred);
                // 3. Add Jof to jump past the loop body if condition is false
                const jof_idx = self.nextInstrAddr();
                try self.addInstr(.{ .Jof = 0 }); // Placeholder
                // 4. Compile loop body
                try self.compile(loop_data.body);
                // 5. Pop the result of the body (loop body result usually discarded)
                try self.addInstr(.Pop);
                // 6. Add Goto to jump back to the condition check
                try self.addInstr(.{ .Goto = cond_addr });
                // 7. Get address after the loop (where Jof jumps)
                const after_loop_addr = self.nextInstrAddr();
                // 8. Patch Jof to jump here
                self.patchJump(jof_idx, after_loop_addr);
                // After the loop finishes (condition becomes false), we need a value on the stack.
                // Loops typically evaluate to 'undefined' or equivalent. Push Undefined using LiteralVal.
                try self.addInstr(.{ .Ldc = .{ .val = "undefined", .type_name = .Undefined } });
            },
            .continue_statement, .break_statement => {
                const tag_name = @tagName(node.*);
                std.debug.print("Compilation error: Unimplemented AST node type: {s}\n", .{tag_name});
                return CompileErrors.UnimplementedAstNode;
            },
        }
    }

    pub fn compileProgram(self: *Compiler, program_node: *const JsonAstNode) !void {
        // Compile the main program node
        try self.compile(program_node);
        // Add the final Done instruction
        try self.addInstr(.Done);
    }

    pub fn printCompiledMicrocode(self: *Compiler) !void {
        const instructions = self.instructions.items;

        std.debug.print("Generated Instructions:\n", .{});
        for (instructions, 0..) |instr, i| {
            std.debug.print("{d}: ", .{i});
            switch (instr) {
                // Update Ldc printing
                .Ldc => |val| std.debug.print("Ldc(val: \"{s}\", type: {any})\n", .{ val.val, val.type_name }),
                .Ld => |val| std.debug.print("Ld(\"{s}\", at: {})\n", .{ val.nam, val.pos }),
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
                        // Assuming Param has a 'name' field
                        std.debug.print("\"{s}\"", .{param.nam});
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

// Keep main for basic testing if needed, but compiler_test.zig is primary
pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var compiler = Compiler.init(allocator);
    defer compiler.deinit();

    // Example AST: let x = 1 + 2; x using JsonAstNode with LiteralVal
    // Assuming default integer type is i32
    var one = JsonAstNode{ .lit = .{ .val = "1", .type_name = .i32 } };
    var two = JsonAstNode{ .lit = .{ .val = "2", .type_name = .i32 } };
    var add_expr = JsonAstNode{ .arith = .{ .sym = .{ .arith = .Add }, .first = &one, .second = &two } };
    var var_decl = JsonAstNode{ .assign = .{ .nam = "x", .val = &add_expr, .is_mut = false } };
    var load_x = JsonAstNode{ .nam = "x" };

    var statements_slice = [_]*JsonAstNode{
        &var_decl,
        &load_x,
    };

    const program = JsonAstNode{ .seq = .{ .stmts = &statements_slice } };

    std.debug.print("Compiling program: let x = 1 + 2; x\n", .{});
    try compiler.compileProgram(&program);

    try compiler.printCompiledMicrocode();
}
