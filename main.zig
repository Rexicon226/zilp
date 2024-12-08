const std = @import("std");

const Solver = struct {
    /// The number of equations provided that constrain the output.
    ///
    /// A constraint looks like: 2x + 5y <= 6.
    constraints: u64,
    /// The number of variables in each equation. This includes the objective
    /// and the constraints.
    ///
    /// 2x + 5y has two variables.
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

    fn initRandom(
        allocator: std.mem.Allocator,
        random: std.Random,
        constraints: u64,
        variables: u64,
    ) !Solver {
        _ = random;

        const solver = try Solver.init(allocator, constraints, variables);
        return solver;
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

    fn solve(solver: *Solver) void {
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

        for (0..solver.variables) |j| {
            var value: f32 = 0;
            for (0..solver.constraints) |i| {
                if (solver.table[i][j] == 1) {
                    value = solver.table[i][solver.num_cols - 1];
                    break;
                }
            }
            std.debug.print("x{d} = {d:.2}\n", .{ j + 1, value });
        }
        std.debug.print("optimal value: {d:.2}\n", .{solver.table[solver.num_rows - 1][solver.num_cols - 1]});
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

        try stream.writeAll("non-negativity: ");
        for (0..solver.variables) |i| {
            try stream.print("X{d} >= 0 ", .{i + 1});
        }
        try stream.writeAll("\n");
    }
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var prng = std.Random.DefaultPrng.init(0);
    const random = prng.random();

    var solver = try Solver.initRandom(allocator, random, 2, 2);
    defer solver.deinit(allocator);

    // x + 2y <= 6
    solver.setConstraint(0, &.{ 1, 2 }, 6);

    // 3x + 2y <= 12
    solver.setConstraint(1, &.{ 3, 2 }, 12);

    // 3x + 5y
    solver.setObjective(&.{ 3, 5 });

    const stdout = std.io.getStdOut().writer();
    try solver.dump(stdout);

    solver.solve();
}
