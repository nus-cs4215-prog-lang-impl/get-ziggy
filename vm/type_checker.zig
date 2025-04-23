const std = @import("std");
const Allocator = std.mem.Allocator;

const TypeEnvironment = @import("type_environment.zig").TypeEnvironment;
const SymbolInfo = @import("type_environment.zig").SymbolInfo;
const types = @import("types.zig");
const BinaryOperation = types.BinaryOperation;
const BinaryOperator = types.BinaryOperator;
const CompileErrors = types.CompileErrors;
const FunctionSignature = types.FunctionSignature;
const JsonAstNode = types.JsonAstNode;
const LiteralVal = types.LiteralVal;
const LogicalOperator = types.LogicalOperator;
const Param = types.Param;
const TypeName = types.TypeName;
const UnaryOperator = types.UnaryOperator;

pub const TypeChecker = struct {
    alloc: Allocator,
    env: TypeEnvironment,

    pub fn init(alloc: Allocator) TypeChecker {
        var checker = TypeChecker{
            .alloc = alloc,
            .env = TypeEnvironment.init(alloc),
        };
        checker.env.pushFrame() catch @panic("Failed to push global frame");
        //checker.addBuiltins(&checker.env) catch @panic("Failed to add builtins");
        return checker;
    }

    pub fn deinit(self: *TypeChecker) void {
        self.env.deinit();
    }

    // fn addBuiltins(env: *TypeEnvironment) !void

    fn expectType(self: *TypeChecker, node: *const JsonAstNode, expected: TypeName) !void {
        const actual_info = try self.check(node);
        if (actual_info.baseType() != expected) {
            std.debug.print("Type Error: Expected type '{any}', found '{any}'\n", .{ expected, actual_info.baseType() });
            return error.TypeMismatch;
        }
    }

    fn expectBoolean(self: *TypeChecker, node: *const JsonAstNode) !void {
        try self.expectType(node, .Bool);
    }

    fn expectNumeric(self: *TypeChecker, node: *const JsonAstNode) !SymbolInfo {
        const info = try self.check(node);
        if (!info.baseType().isNumeric()) {
            std.debug.print("Type Error: Expected numeric type, found '{any}'\n", .{info.baseType()});
            return error.TypeMismatch;
        }
        return info;
    }

    // Check function now returns the type info or an error
    pub fn check(self: *TypeChecker, node: *const JsonAstNode) CompileErrors!SymbolInfo {
        return switch (node.*) {
            .lit => |lit_data| return self.checkLit(lit_data),
            .nam => |name| return self.checkVal(name),
            .fun => |fun_data| return self.checkFunc(fun_data.nam, fun_data.params, fun_data.body, fun_data.return_type),
            .app => |app_data| return self.checkApp(app_data.nam, app_data.args),
            .comp => |bin_op| self.checkComp(bin_op),
            .logic => |bin_op| self.checkLogic(bin_op),
            .arith => |bin_op| self.checkArith(bin_op),
            .borrow => |borrow_data| self.checkBorrow(borrow_data.first),
            .borrow_mut => |check_data| self.checkBorrowMut(check_data.first),
            .deref => return CompileErrors.UnimplementedAstNode,
            .neg => return CompileErrors.UnimplementedAstNode,
            .question => return CompileErrors.UnimplementedAstNode,
            .seq => |seq_data| self.checkSeq(seq_data.stmts),
            .blk => |blk_data| self.checkBlk(blk_data.body),
            .assign => |assign_data| self.checkAssign(assign_data.nam, assign_data.val, assign_data.is_mut, assign_data.type_name),
            .reassign => |reassign_data| self.checkReassign(reassign_data.first, reassign_data.second),
            .compound_assign => return CompileErrors.UnimplementedAstNode,
            .type_cast => return CompileErrors.UnimplementedAstNode,
            .cond => return CompileErrors.UnimplementedAstNode,
            .while_loop => return CompileErrors.UnimplementedAstNode,
            .return_statement => return CompileErrors.UnimplementedAstNode,
            .continue_statement => return CompileErrors.UnimplementedAstNode,
            .break_statement => return CompileErrors.UnimplementedAstNode,
        };
    }

    fn checkLit(self: *TypeChecker, lit: LiteralVal) !SymbolInfo {
        _ = self;
        return SymbolInfo{
            .type_name = lit.type_name,
            .is_mut = false,
        };
    }

    fn checkVal(self: *TypeChecker, nam: []const u8) !SymbolInfo {
        std.debug.print("Checking value: {s}\n", .{nam});
        if (self.env.lookup(nam)) |symbol_info| {
            if (symbol_info.is_borrow_mut) {
                std.debug.print("Borrow Error: Cannot use '{s}' because it is currently mutably borrowed.\n", .{nam});
                return error.ReadOfMutablyBorrowed;
            }
            return symbol_info;
        } else {
            std.debug.print("Type Error: Unbound name '{s}'.\n", .{nam});
            return error.UnboundName;
        }
    }

    fn checkLogic(self: *TypeChecker, bin_op: BinaryOperation) !SymbolInfo {
        try self.expectBoolean(bin_op.first);
        try self.expectBoolean(bin_op.second);
        return SymbolInfo.create(.Bool, false);
    }

    fn checkComp(self: *TypeChecker, bin_op: BinaryOperation) !SymbolInfo {
        const lhs_info = try self.check(bin_op.first);
        const rhs_info = try self.check(bin_op.second);

        // Basic comparison: require types to be the same for now
        // TODO: Allow comparison between different numeric types?
        if (lhs_info.baseType() != rhs_info.baseType()) {
            std.debug.print("Type Error: Cannot compare values of different types ('{any}' and '{any}')\n", .{ lhs_info.baseType(), rhs_info.baseType() });
            return error.TypeMismatch;
        }

        // Check if the type supports comparison (e.g., numeric, bool, String)
        switch (lhs_info.baseType()) {
            .i32, .u32, .i64, .u64, .f64, .Bool, .String => {}, // Allowed
            else => {
                std.debug.print("Type Error: Type '{any}' does not support comparison operations.\n", .{lhs_info.baseType()});
                return error.InvalidOperation;
            },
        }

        return SymbolInfo.create(.Bool, false);
    }

    fn checkArith(self: *TypeChecker, bin_op: BinaryOperation) !SymbolInfo {
        const lhs_info = try self.expectNumeric(bin_op.first);
        const rhs_info = try self.expectNumeric(bin_op.second);

        // Require exact type match for arithmetic for now
        if (lhs_info.baseType() != rhs_info.baseType()) {
            std.debug.print("Type Error: Arithmetic operations require operands of the same type ('{any}' and '{any}')\n", .{ lhs_info.baseType(), rhs_info.baseType() });
            return error.TypeMismatch;
        }

        // Check for integer-only operations (%, bitwise, shift)
        const op = bin_op.sym.arith;
        if (op == .Mod or op == .Bitand or op == .Bitor or op == .Bitxor or op == .Shl or op == .Shr) {
            if (!lhs_info.baseType().isInteger()) {
                std.debug.print("Type Error: Operator '{any}' requires integer operands, found '{any}'.\n", .{ op, lhs_info.baseType() });
                return error.InvalidOperation;
            }
        }

        // Result type is the same as operands
        return SymbolInfo.create(lhs_info.baseType(), false);
    }

    fn checkSeq(self: *TypeChecker, stmts: []*JsonAstNode) !SymbolInfo {
        if (stmts.len == 0) {
            return SymbolInfo.unit();
        }
        var last_info = SymbolInfo.unit();
        for (stmts) |stmt| {
            // std.debug.print("Checking statement: {any}\n", .{stmt.*});
            last_info = try self.check(stmt);
        }
        return last_info;
    }

    fn checkAssign(self: *TypeChecker, nam: []const u8, val: *const JsonAstNode, is_mut: bool, type_name: ?TypeName) !SymbolInfo {
        const val_type = try self.check(val);
        // std.debug.print("val checking: {any}\n", .{val_type});
        const assigned_type = val_type.baseType(); // Infer type from value by default

        // If type annotation exists, check compatibility and use annotation
        if (type_name) |annotated_type| {
            if (assigned_type != annotated_type) {
                std.debug.print("Type Error: Initializer type '{any}' does not match annotation '{any}' for '{s}'.\n", .{ assigned_type, annotated_type, nam });
                return CompileErrors.TypeMismatch;
            }
        }

        // std.debug.print("Assigning '{s}' type '{any}' (mut: {any})\n", .{ nam, assigned_type, is_mut });
        try self.env.addBinding(nam, SymbolInfo.create(assigned_type, is_mut));

        // Assignment statement itself has Unit type
        return SymbolInfo.unit();
    }

    fn checkReassign(self: *TypeChecker, first: *JsonAstNode, second: *JsonAstNode) !SymbolInfo {
        const target_name = switch (first.*) {
            .nam => |n| n,
            else => {
                std.debug.print("Type Error: Left-hand side of assignment must be a variable name.\n", .{});
                return error.InvalidOperation;
            },
        };

        const target_info = try self.checkVal(target_name);

        // Borrow Checking
        if (target_info.is_borrow_mut or target_info.borrow_count_imm > 0) {
            std.debug.print("Type Error: Cannot assign to borrowed variable '{s}'.\n", .{target_name});
            return error.AssignmentIsBorrowed;
        }

        if (!target_info.is_mut) {
            std.debug.print("Type Error: Cannot assign to immutable variable '{s}'.\n", .{target_name});
            return error.MutationOfImmutable;
        }

        const val_info = try self.check(second);

        if (target_info.baseType() != val_info.baseType()) {
            std.debug.print("Type Error: Cannot assign value of type '{any}' to variable '{s}' of type '{any}'.\n", .{ val_info.baseType(), target_name, target_info.baseType() });
            return error.TypeMismatch;
        }

        return SymbolInfo.unit();
    }

    fn checkBlk(self: *TypeChecker, body: *JsonAstNode) !SymbolInfo {
        try self.env.pushFrame();
        defer self.env.popFrame();
        return try self.check(body);
    }

    fn checkFunc(self: *TypeChecker, nam: []const u8, params: []Param, body: ?*JsonAstNode, return_type: ?TypeName) !SymbolInfo {
        const signature = FunctionSignature{
            .params = params,
            .return_type = return_type,
        };

        try self.env.addBinding(nam, SymbolInfo.createFunc(signature));
        if (body) |body_node| {
            try self.env.pushFrame(); // Create a new frame
            defer self.env.popFrame();

            // NOTE: We're pushing the params into the same frame
            for (params) |param| {
                try self.env.addBinding(param.nam, SymbolInfo.create(param.type_name, param.is_mut));
            }

            const return_info = try self.check(body_node);
            if (return_type) |expected_type| {
                if (return_info.baseType() != expected_type) {
                    std.debug.print("Type Error: Function '{s}' expected return type '{any}', found '{any}'.\n", .{ nam, expected_type, return_info.baseType() });
                    return error.TypeMismatch;
                }
            }
        }
        return SymbolInfo.unit();
    }

    fn checkApp(self: *TypeChecker, nam: []const u8, args: []*JsonAstNode) !SymbolInfo {
        if (self.env.lookup(nam)) |symbol_info| {
            if (!symbol_info.isFunc()) {
                std.debug.print("Type Error: '{s}' is not a function.\n", .{nam});
                return error.InvalidOperation;
            }
            const func_sig = symbol_info.func_sig.?;
            // check arity
            if (args.len != func_sig.params.len) {
                std.debug.print("Type Error: Function '{s}' expected {d} arguments, found {d}.\n", .{ nam, func_sig.params.len, args.len });
                return error.ArgumentCountMismatch;
            }

            for (args, func_sig.params) |arg, param| {
                const arg_info = try self.check(arg);
                if (arg_info.baseType() != param.type_name) {
                    std.debug.print("Type Error: Argument type '{any}' does not match expected type '{any}' for parameter '{s}'.\n", .{ arg_info.baseType(), param.type_name, param.nam });
                    return error.TypeMismatch;
                }
            }

            if (func_sig.return_type) |return_type| {
                return SymbolInfo.create(return_type, false);
            } else {
                return SymbolInfo.unit();
            }
        } else {
            std.debug.print("Type Error: Unbound name '{s}'.\n", .{nam});
            return error.UnboundName;
        }
    }

    fn checkBorrow(self: *TypeChecker, first: *JsonAstNode) !SymbolInfo {
        const target_name = switch (first.*) {
            .nam => |n| n,
            else => {
                std.debug.print("Borrow Error: Cannot take immutable reference of a non-variable expression.\n", .{});
                return error.InvalidOperation; // Or specific borrow error
            },
        };

        const target_info = try self.checkVal(target_name);
        try self.env.incrementImmutableBorrow(target_name);

        return SymbolInfo.createRef(target_info.baseType(), false);
    }

    fn checkBorrowMut(self: *TypeChecker, val_node: *const JsonAstNode) !SymbolInfo {
        const target_name = switch (val_node.*) {
            .nam => |n| n,
            else => {
                std.debug.print("Borrow Error: Cannot take mutable reference of a non-variable expression.\n", .{});
                return error.InvalidOperation;
            },
        };

        const target_info = try self.checkVal(target_name);

        try self.env.setMutableBorrow(target_name);
        // TODO: Lifetime start.

        return SymbolInfo.createRef(target_info.baseType(), true);
    }
};
