const std = @import("std");
const Allocator = std.mem.Allocator;
const types = @import("types.zig");
const TypeName = types.TypeName;
const FunctionSignature = types.FunctionSignature;
const CompileErrors = types.CompileErrors;
const LifetimeId = types.LifetimeId;

const ArrayList = std.ArrayList;
const StringHashMap = std.StringHashMap;

// TODO: account for functions
// TODO: ownership stuff should be here as well
pub const SymbolInfo = struct {
    type_name: TypeName,
    is_mut: bool,
    func_sig: ?FunctionSignature = null,

    // Borrow Stuff
    is_reference: bool = false,
    is_ref_mut: bool = false,

    // Lifetime
    allocator: Allocator,
    declaration_lifetime: ?LifetimeId = null,
    reference_lifetime: ?LifetimeId = null,
    active_immutable_borrows: ArrayList(LifetimeId),
    active_mutable_borrow: ?LifetimeId = null,

    pub fn deinit(self: *SymbolInfo) void {
        self.active_immutable_borrows.deinit();
    }

    pub fn baseType(self: SymbolInfo) TypeName {
        return self.type_name; // Assumes type_name stores the underlying type T for &T, &mut T etc.
    }

    pub fn create(alloc: Allocator, type_name: TypeName, is_mut: bool, lifetime: LifetimeId) SymbolInfo {
        return .{ .allocator = alloc, .type_name = type_name, .is_mut = is_mut, .declaration_lifetime = lifetime, .active_immutable_borrows = ArrayList(LifetimeId).init(alloc) };
    }

    pub fn createFunc(alloc: Allocator, func_sig: FunctionSignature, lifetime: LifetimeId) SymbolInfo {
        return .{ .allocator = alloc, .type_name = .Undefined, .is_mut = false, .func_sig = func_sig, .declaration_lifetime = lifetime, .active_immutable_borrows = ArrayList(LifetimeId).init(alloc) };
    }

    pub fn unit(alloc: Allocator) SymbolInfo {
        return .{ .allocator = alloc, .type_name = TypeName.Undefined, .is_mut = false, .active_immutable_borrows = ArrayList(LifetimeId).init(alloc) };
    }

    pub fn isFunc(self: SymbolInfo) bool {
        return self.func_sig != null;
    }

    pub fn createRef(alloc: Allocator, pointed_to_type: TypeName, is_mut_ref: bool, lifetime: LifetimeId) SymbolInfo {
        return .{
            .allocator = alloc,
            .type_name = pointed_to_type,
            .is_mut = false,
            .is_reference = true,
            .is_ref_mut = is_mut_ref,
            .func_sig = null,
            .declaration_lifetime = lifetime,
            .active_immutable_borrows = ArrayList(LifetimeId).init(alloc),
        };
    }
};

const TypeFrame = StringHashMap(SymbolInfo);

pub const TypeEnvironment = struct {
    alloc: Allocator,
    frames: std.ArrayList(TypeFrame),

    pub fn init(alloc: Allocator) TypeEnvironment {
        return .{
            .alloc = alloc,
            .frames = std.ArrayList(TypeFrame).init(alloc),
        };
    }

    pub fn deinit(self: *TypeEnvironment) void {
        // Deinitialize any remaining frames (should ideally only be the global frame if used correctly)
        while (self.frames.items.len > 0) {
            self.popFrame(); // Use popFrame to ensure proper cleanup
        }
        self.frames.deinit(); // Deinit the ArrayList itself
    }

    pub fn pushFrame(self: *TypeEnvironment) !void {
        try self.frames.append(TypeFrame.init(self.alloc));
        std.debug.print("Extend scope. Depth: {}\n", .{self.frames.items.len});
    }

    pub fn popFrame(self: *TypeEnvironment) void {
        if (self.frames.items.len > 0) {
            // Pop the frame from the list
            const ending_lifetime = self.currentLifetime();
            var frame = self.frames.pop().?;

            // Lifetime Cleanup: iterate through all variables in the remaining outer scopes.
            // Remove any borrows that were created  within the scope that just ended
            for (self.frames.items) |*outer_frame| {
                var iter = outer_frame.valueIterator();

                while (iter.next()) |symbol_info_ptr| {
                    if (symbol_info_ptr.active_mutable_borrow) |borrower_lifetime| {
                        if (borrower_lifetime == ending_lifetime) {
                            std.debug.print("Lifetime End: Releasing mutable borrow (lifetime {d}) from variable declared in lifetime {?d}\n", .{ ending_lifetime, symbol_info_ptr.declaration_lifetime });
                            symbol_info_ptr.active_mutable_borrow = null;
                        }
                    }

                    var i: usize = 0;
                    while (i < symbol_info_ptr.active_immutable_borrows.items.len) {
                        const borrower_lifetime = symbol_info_ptr.active_immutable_borrows.items[i];
                        if (borrower_lifetime == ending_lifetime) {
                            std.debug.print("Lifetime End: Releasing immutable borrow (lifetime {d}) from variable declared in lifetime {?d}\n", .{ ending_lifetime, symbol_info_ptr.declaration_lifetime });
                            _ = symbol_info_ptr.active_immutable_borrows.swapRemove(i);
                        } else {
                            i += 1;
                        }
                    }
                }
            }

            var iter = frame.keyIterator();
            while (iter.next()) |key_ptr| {
                self.alloc.free(key_ptr.*);
            }

            var val_iter = frame.valueIterator();
            while (val_iter.next()) |symbol_info_ptr| {
                symbol_info_ptr.deinit();
            }

            // Deinitialize the hash map itself
            frame.deinit();

            std.debug.print("Reduce scope. Depth: {}\n", .{self.frames.items.len});
        } else {
            // This case should ideally not happen if push/pop are balanced,
            // but it's good practice to handle it.
            std.debug.print("Warning: Attempted to pop frame from empty environment.\n", .{});
            // @panic("Attempted to pop frame from empty or global-only environment");
        }
    }

    pub fn addBinding(self: *TypeEnvironment, name: []const u8, symbol_info: SymbolInfo) !void {
        const current_frame = self.currentFrame();
        const owned_name = try self.alloc.dupe(u8, name);
        errdefer self.alloc.free(owned_name); // Free if put fails

        if (current_frame.contains(owned_name)) {
            std.debug.print("Type Error: Redeclaration of '{s}' in the same scope.\n", .{owned_name});
            // No need to free owned_name here, errdefer handles it if put fails.
            // If contains() is true, put won't be called. We need to free manually.
            self.alloc.free(owned_name);
            return error.SymbolAlreadyDeclared;
        }

        // If put fails, errdefer will free owned_name.
        try current_frame.put(owned_name, symbol_info);

        // Debug prints
        if (symbol_info.isFunc()) {
            std.debug.print("Declared '{s}' (type: {any}, mut: {any}, func: {any}) in current frame.\n", .{ owned_name, symbol_info.type_name, symbol_info.is_mut, symbol_info.func_sig });
        } else {
            std.debug.print("Declared '{s}' (type: {any}, mut: {any}) in current frame.\n", .{ owned_name, symbol_info.type_name, symbol_info.is_mut });
        }
    }

    pub fn lookup(self: *const TypeEnvironment, name: []const u8) ?SymbolInfo {
        var i = self.frames.items.len;
        while (i > 0) {
            i -= 1;
            const frame = &self.frames.items[i];
            if (frame.get(name)) |typ| {
                return typ;
            }
        }
        return null;
    }

    pub fn currentLifetime(self: *const TypeEnvironment) LifetimeId {
        // Lifetime ID is simply the index of the frame (0 = global, 1 = first nested, etc.)
        // Ensure there's at least one frame before calling this.
        if (self.frames.items.len == 0) {
            @panic("Attempted to get current lifetime from empty environment");
        }
        return self.frames.items.len - 1;
    }

    fn currentFrame(self: *TypeEnvironment) *TypeFrame {
        if (self.frames.items.len == 0) {
            // This can happen if addBinding is called before the first pushFrame.
            // Consider adding an initial frame in init or handling this case explicitly.
            @panic("Attempted to access current frame from empty environment");
        }
        return &self.frames.items[self.frames.items.len - 1];
    }

    fn lookupMut(self: *TypeEnvironment, name: []const u8) ?*SymbolInfo {
        var i = self.frames.items.len;
        while (i > 0) {
            i -= 1;
            const frame = &self.frames.items[i];
            // Use getPtr to get a mutable pointer if the key exists
            if (frame.getPtr(name)) |info_ptr| {
                return info_ptr;
            }
        }
        return null;
    }

    pub fn incrementImmutableBorrow(self: *TypeEnvironment, name: []const u8, lifetime: LifetimeId) CompileErrors!void {
        if (self.lookupMut(name)) |info_ptr| {
            if (info_ptr.active_mutable_borrow != null) {
                std.debug.print("Borrow Error: Cannot borrow '{s}' as immutable because it is already mutably borrowed.\n", .{name});
                return error.BorrowConflictMutable;
            }

            try info_ptr.active_immutable_borrows.append(lifetime);
            std.debug.print("Added immutable borrow of '{s}' by lifetime {d}. Count: {d}\n", .{ name, lifetime, info_ptr.active_immutable_borrows.items.len });
        } else {
            std.debug.print("Internal Error: Failed to find '{s}' to increment borrow count.\n", .{name});
            return error.UnboundName; // Should not happen if called after a successful lookup
        }
    }

    pub fn setMutableBorrow(self: *TypeEnvironment, name: []const u8, lifetime: LifetimeId) CompileErrors!void {
        if (self.lookupMut(name)) |info_ptr| {
            if (info_ptr.active_mutable_borrow != null) {
                std.debug.print("Borrow Error: Cannot borrow '{s}' as mutable because it is already mutably borrowed.\n", .{name});
                return error.BorrowConflictMutable;
            }
            if (info_ptr.active_immutable_borrows.items.len > 0) {
                std.debug.print("Borrow Error: Cannot borrow '{s}' as mutable because it is already immutably borrowed ({d} times).\n", .{ name, info_ptr.active_immutable_borrows.items.len });
                return error.BorrowConflictImmutable;
            }

            if (!info_ptr.is_mut) {
                // Check if the original variable binding allows mutation
                std.debug.print("Borrow Error: Cannot mutably borrow immutable variable '{s}'.\n", .{name});
                return error.MutationOfImmutable;
            }
            info_ptr.active_mutable_borrow = lifetime;
            std.debug.print("Set mutable borrow flag for '{s}'.\n", .{name});
        } else {
            std.debug.print("Internal Error: Failed to find '{s}' to set mutable borrow.\n", .{name});
            return error.UnboundName;
        }
    }

    pub fn releaseMutableBorrow(self: *TypeEnvironment, name: []const u8) CompileErrors!void {
        if (self.lookupMut(name)) |info_ptr| {
            if (!info_ptr.is_borrow_mut) {
                std.debug.print("Internal Warning: Attempted to release mutable borrow for '{s}' when it was not mutably borrowed.\n", .{name});
                // This might indicate a logic error
            } else {
                info_ptr.is_borrow_mut = false;
                std.debug.print("Released mutable borrow flag for '{s}'.\n", .{name});
            }
        } else {
            std.debug.print("Internal Error: Failed to find '{s}' to release mutable borrow.\n", .{name});
            return error.UnboundName;
        }
    }
};
