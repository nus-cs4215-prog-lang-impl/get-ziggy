const std = @import("std");
const Allocator = std.mem.Allocator;

const TypeEnvironment = @import("type_environment.zig").TypeEnvironment;
const SymbolInfo = @import("type_environment.zig").SymbolInfo;
const types = @import("types.zig");
const BinaryOperator = types.BinaryOperator;
const CompileErrors = types.CompileErrors;
const JsonAstNode = types.JsonAstNode;
const LiteralVal = types.LiteralVal;
const LogicalOperator = types.LogicalOperator;
const Param = types.Param;
const TypeName = types.TypeName;
const UnaryOperator = types.UnaryOperator;

pub const TypeChecker = struct {
    alloc: Allocator,
    env: *TypeEnvironment,

    pub fn init(alloc: Allocator) TypeChecker {
        const checker = TypeChecker{
            .alloc = alloc,
            .env = TypeEnvironment.init(alloc),
        };
        checker.env.pushFrame() catch @panic("Failed to push global frame");
        //checker.addBuiltins catch @panic("Failed to add builtins");
        return checker;
    }

    pub fn deinit(self: *TypeChecker) void {
        self.env.deinit();
    }

    // fn addBuiltins(self: *TypeChecker) !void

    pub fn check(self: *TypeChecker, node: *const JsonAstNode) !void {
        return switch (node.*) {
            .lit => |lit_data| self.checkLit(lit_data),
            .nam => |name| self.checkValue(name),
            .app => return CompileErrors.UnimplementedAstNode,
            .comp => return CompileErrors.UnimplementedAstNode,
            .logic => return CompileErrors.UnimplementedAstNode,
            .arith => return CompileErrors.UnimplementedAstNode,
            .borrow => return CompileErrors.UnimplementedAstNode,
            .borrow_mut => return CompileErrors.UnimplementedAstNode,
            .deref => return CompileErrors.UnimplementedAstNode,
            .neg => return CompileErrors.UnimplementedAstNode,
            .question => return CompileErrors.UnimplementedAstNode,
            .seq => return CompileErrors.UnimplementedAstNode,
            .blk => return CompileErrors.UnimplementedAstNode,
            .assign => return CompileErrors.UnimplementedAstNode,
            .reassign => return CompileErrors.UnimplementedAstNode,
            .compound_assign => return CompileErrors.UnimplementedAstNode,
            .type_cast => return CompileErrors.UnimplementedAstNode,
            .cond => return CompileErrors.UnimplementedAstNode,
            .fun => return CompileErrors.UnimplementedAstNode,
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
        if (self.env.lookup(nam)) |symbol_info| {
            return symbol_info;
        } else {
            std.debug.print("Type Error: Unbound name '{s}'.\n", .{nam});
            return error.UnboundName;
        }
    }
};
