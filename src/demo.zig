const std = @import("std");
const zilp = @import("zilp");

const Simplex = zilp.Simplex;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var prng = std.Random.DefaultPrng.init(0);
    const random = prng.random();

    var solver = try Simplex.init(allocator, 10_000, 10_000);
    defer solver.deinit(allocator);

    try solver.randomize(allocator, random);

    // const stdout = std.io.getStdOut().writer();
    // try solver.dump(stdout);

    const result = solver.solve();
    std.debug.print("optimal value: {d:.2}\n", .{result});
}
