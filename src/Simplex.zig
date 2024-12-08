constraints: u64,
variables: u64,
table: [][]f32,

num_cols: u64,
num_rows: u64,

pub fn init(
    allocator: std.mem.Allocator,
    constraints: u64,
    variables: u64,
) !Simplex {
    var solver: Simplex = .{
        .constraints = constraints,
        .variables = variables,
        .table = undefined,
        .num_cols = variables + constraints + 1, // variables + slack + RHS
        .num_rows = constraints + 1, // includes the objective row
    };

    const table = try allocator.alloc([]f32, solver.num_rows);
    for (table) |*col| {
        col.* = try allocator.alloc(f32, solver.num_cols);
        @memset(col.*, 0);
    }
    solver.table = table;

    return solver;
}

pub fn randomize(
    solver: *Simplex,
    allocator: std.mem.Allocator,
    random: std.Random,
) !void {
    // set random constraints
    for (0..solver.constraints) |i| {
        const coefficients = try allocator.alloc(f32, solver.variables);
        defer allocator.free(coefficients);

        for (coefficients) |*coef| {
            coef.* = random.floatExp(f32) * 1_000;
        }
        const rhs_value = random.floatExp(f32) * 1_000;
        solver.setConstraint(i, coefficients, rhs_value);
    }

    // set random objective
    const coefficients = try allocator.alloc(f32, solver.variables);
    defer allocator.free(coefficients);
    for (coefficients) |*coef| {
        coef.* = random.floatExp(f32) * 1_000;
    }
    solver.setObjective(coefficients);
}

pub fn deinit(
    solver: *const Simplex,
    allocator: std.mem.Allocator,
) void {
    for (solver.table) |row| allocator.free(row);
    allocator.free(solver.table);
}

pub fn setConstraint(
    solver: *Simplex,
    row: u64,
    coefficients: []const f32,
    value: f32,
) void {
    @memcpy(solver.table[row][0..solver.variables], coefficients);

    solver.table[row][solver.variables + row] = 1.0; // slack variable
    solver.table[row][solver.num_cols - 1] = value; // RHS value
}

pub fn setObjective(
    solver: *Simplex,
    coef: []const f32,
) void {
    for (
        solver.table[solver.num_rows - 1][0..solver.variables],
        coef,
    ) |*dst, src| {
        dst.* = -src;
    }
}

pub fn solve(solver: *Simplex) f32 {
    var maybe_pc: ?u64 = null;
    var maybe_pr: ?u64 = null;
    var min_ratio: ?f32 = null;

    const objective = solver.table[solver.num_rows - 1];

    while (true) {
        maybe_pc = null;

        for (0..solver.num_cols - 1) |i| {
            if (objective[i] < 0) {
                if (maybe_pc == null or
                    objective[i] <
                    objective[maybe_pc.?])
                {
                    maybe_pc = i;
                }
            }
        }

        if (maybe_pc == null) break; // optimal solution found
        const pc = maybe_pc.?;

        maybe_pr = null;
        min_ratio = null;
        for (0..solver.constraints) |i| {
            if (solver.table[i][pc] > 0) {
                const ratio = solver.table[i][solver.num_cols - 1] / solver.table[i][pc];
                if (maybe_pr == null or
                    min_ratio == null or
                    ratio < min_ratio.?)
                {
                    min_ratio = ratio;
                    maybe_pr = i;
                }
            }
        }

        if (maybe_pr == null) std.debug.panic("unbounded solution\n", .{});
        const pr = maybe_pr.?;

        // perform a pivot
        const pivot = solver.table[pr][pc];
        for (solver.table[pr]) |*item| {
            item.* /= pivot;
        }

        for (0..solver.num_rows) |i| {
            if (i != pr) {
                const factor = solver.table[i][pc];
                for (solver.table[i], solver.table[pr]) |*dst, src| {
                    dst.* -= factor * src;
                }
            }
        }
    }

    return solver.table[solver.num_rows - 1][solver.num_cols - 1];
}

fn dump(solver: *Simplex, stream: anytype) !void {
    try stream.writeAll("objective, Maximize Z = ");
    for (0..solver.variables) |i| {
        try stream.print("{d:.2}X{d} ", .{
            -solver.table[solver.num_rows - 1][i],
            i + 1,
        });
    }
    try stream.writeAll("\n");

    try stream.writeAll("constraints:\n");
    for (solver.table[0..solver.constraints]) |row| {
        for (0..solver.variables) |i| {
            try stream.print("{d:.2}X{d} ", .{ row[i], i + 1 });
        }
        try stream.print("<= {d:.2}\n", .{row[solver.num_cols - 1]});
    }
}

const std = @import("std");
const Simplex = @This();
