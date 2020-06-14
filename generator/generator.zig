const std = @import("std");
const reg = @import("registry.zig");
const xml = @import("xml.zig");
const parseXml = @import("registry/parse.zig").parseXml;
const Allocator = std.mem.Allocator;
const FeatureLevel = reg.FeatureLevel;

fn cmpFeatureLevels(a: FeatureLevel, b: FeatureLevel) std.math.Order {
    if (a.major > b.major) {
        return .gt;
    } if (a.major < b.major) {
        return .lt;
    }

    if (a.minor > b.minor) {
        return .gt;
    } else if (a.minor < b.minor) {
        return .lt;
    }

    return .eq;
}

const DeclarationResolver = struct {
    const DeclarationSet = std.StringHashMap(void);
    const EnumExtensionMap = std.StringHashMap(std.ArrayList(reg.Enum.Field));
    const FieldMap = std.StringHashMap(reg.Enum.Value);

    allocator: *Allocator,
    reg_arena: *Allocator,
    registry: *reg.Registry,
    declarations: DeclarationSet,
    enum_extensions: EnumExtensionMap,
    field_map: FieldMap,

    fn init(allocator: *Allocator, reg_arena: *Allocator, registry: *reg.Registry) DeclarationResolver {
        return .{
            .allocator = allocator,
            .reg_arena = reg_arena,
            .registry = registry,
            .declarations = DeclarationSet.init(allocator),
            .enum_extensions = EnumExtensionMap.init(allocator),
            .field_map = FieldMap.init(allocator),
        };
    }

    fn deinit(self: DeclarationResolver) void {
        var it = self.enum_extensions.iterator();
        while (it.next()) |kv| {
            kv.value.deinit();
        }

        self.field_map.deinit();
        self.enum_extensions.deinit();
        self.declarations.deinit();
    }

    fn putEnumExtension(self: *DeclarationResolver, enum_name: []const u8, field: reg.Enum.Field) !void {
        const res = try self.enum_extensions.getOrPut(enum_name);
        if (!res.found_existing) {
            res.kv.value = std.ArrayList(reg.Enum.Field).init(self.allocator);
        }

        try res.kv.value.append(field);
    }

    fn addRequire(self: *DeclarationResolver, req: reg.Require) !void {
        for (req.types) |type_name| {
            _ = try self.declarations.put(type_name, {});
        }

        for (req.commands) |command| {
            _ = try self.declarations.put(command, {});
        }

        for (req.extends) |enum_ext| {
            try self.putEnumExtension(enum_ext.extends, enum_ext.field);
        }
    }

    fn mergeEnumFields(self: *DeclarationResolver, name: []const u8, base_enum: *reg.Enum) !void {
        // If there are no extensions for this enum, assume its valid.
        const extensions = self.enum_extensions.get(name) orelse return;

        self.field_map.clear();

        for (base_enum.fields) |field| {
            _ = try self.field_map.put(field.name, field.value);
        }

        // Assume that if a field name clobbers, the value is the same
        for (extensions.value.items) |field| {
            _ = try self.field_map.put(field.name, field.value);
        }

        const new_fields = try self.reg_arena.alloc(reg.Enum.Field, self.field_map.count());

        var it = self.field_map.iterator();
        for (new_fields) |*field| {
            const kv = it.next().?;
            field.* = .{
                .name = kv.key,
                .value = kv.value,
            };
        }

        // Existing base_enum.fields was allocatued by `self.reg_arena`, so
        // it gets cleaned up whenever that is deinited.
        base_enum.fields = new_fields;
    }

    fn resolve(self: *DeclarationResolver) !void {
        for (self.registry.features) |feature| {
            for (feature.requires) |req| {
                try self.addRequire(req);
            }
        }

        for (self.registry.extensions) |ext| {
            for (ext.requires) |req| {
                try self.addRequire(req);
            }
        }

        // Merge all the enum fields.
        // Assume that all keys of enum_extensions appear in `self.registry.decls`
        for (self.registry.decls) |*decl| {
            if (decl.decl_type == .enumeration) {
                try self.mergeEnumFields(decl.name, &decl.decl_type.enumeration);
            }
        }

        // Swap-remove all declarations that are not required.
        // Some declarations may exist in `self.declarations` that do not exit in
        // `self.registry.decls`, these are mostly macros and other stuff not parsed.
        var i: usize = 0;
        var count = self.registry.decls.len;
        while (i < count) {
            const decl = self.registry.decls[i];
            if (self.declarations.contains(decl.name)) {
                i += 1;
            } else {
                count -= 1;
                self.registry.decls[i] = self.registry.decls[count];
            }
        }

        self.registry.decls = self.reg_arena.shrink(self.registry.decls, count);
    }
};

pub const Generator = struct {
    gpa: *Allocator,
    registry_arena: std.heap.ArenaAllocator,
    registry: reg.Registry,

    pub fn init(allocator: *Allocator, spec: *xml.Element) !Generator {
        const result = try parseXml(allocator, spec);
        return Generator{
            .gpa = allocator,
            .registry_arena = result.arena,
            .registry = result.registry,
        };
    }

    pub fn deinit(self: Generator) void {
        self.registry_arena.deinit();
    }

    // Solve registry.declarations according to registry.extensions and registry.features
    pub fn resolveDeclarations(self: *Generator) !void {
        var resolver = DeclarationResolver.init(self.gpa, &self.registry_arena.allocator, &self.registry);
        defer resolver.deinit();
        try resolver.resolve();
    }
};
