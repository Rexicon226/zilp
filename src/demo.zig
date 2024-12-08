const std = @import("std");
const zilp = @import("zilp");

const Simplex = zilp.Simplex;

pub fn main() !void {
    const allocator = std.heap.c_allocator;

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    const input_length = try std.fmt.parseInt(u32, args[1], 10);

    var prng = std.Random.DefaultPrng.init(10);
    const random = prng.random();

    var solver = try Simplex.init(allocator, input_length, 100);
    defer solver.deinit(allocator);

    try solver.randomize(allocator, random);

    var timer = try std.time.Timer.start();
    std.mem.doNotOptimizeAway(solver.solve());
    const time_spent = timer.lap();

    std.debug.print("{}", .{time_spent});
}
