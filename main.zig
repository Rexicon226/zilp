const std = @import("std");

const Solver = struct {
    constraints: u64,
    variables: u64,
    table: [][]f32,

    num_cols: u64,
    num_rows: u64,

    fn init(
        allocator: std.mem.Allocator,
        constraints: u64,
        variables: u64,
    ) !Solver {
        var solver: Solver = .{
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

    fn randomize(
        solver: *Solver,
        allocator: std.mem.Allocator,
        random: std.Random,
    ) !void {
        // set random constraints
        for (0..solver.constraints) |i| {
            const coefficients = try allocator.alloc(f32, solver.variables);
            defer allocator.free(coefficients);

            for (coefficients) |*coef| {
                coef.* = random.floatExp(f32) * 10_000;
            }
            const rhs_value = random.floatExp(f32) * 10_000;
            solver.setConstraint(i, coefficients, rhs_value);
        }

        // set random objective
        const coefficients = try allocator.alloc(f32, solver.variables);
        defer allocator.free(coefficients);
        for (coefficients) |*coef| {
            coef.* = random.floatExp(f32) * 10_000;
        }
        solver.setObjective(coefficients);
    }

    fn deinit(
        solver: *const Solver,
        allocator: std.mem.Allocator,
    ) void {
        for (solver.table) |row| allocator.free(row);
        allocator.free(solver.table);
    }

    fn setConstraint(
        solver: *Solver,
        row: u64,
        coefficients: []const f32,
        value: f32,
    ) void {
        @memcpy(solver.table[row][0..solver.variables], coefficients);

        solver.table[row][solver.variables + row] = 1.0; // slack variable
        solver.table[row][solver.num_cols - 1] = value; // RHS value
    }

    fn setObjective(
        solver: *Solver,
        coef: []const f32,
    ) void {
        for (
            solver.table[solver.num_rows - 1][0..solver.variables],
            coef,
        ) |*dst, src| {
            dst.* = -src;
        }
    }

    fn solve(solver: *Solver) f32 {
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

    fn dump(solver: *Solver, stream: anytype) !void {
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
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var prng = std.Random.DefaultPrng.init(0);
    const random = prng.random();

    var solver = try Solver.init(allocator, 10_000, 10_000);
    defer solver.deinit(allocator);

    try solver.randomize(allocator, random);

    // const stdout = std.io.getStdOut().writer();
    // try solver.dump(stdout);

    const result = solver.solve();
    std.debug.print("optimal value: {d:.2}\n", .{result});
}
