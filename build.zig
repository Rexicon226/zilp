const std = @import("std");

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const lib = b.addModule("zilp", .{
        .root_source_file = b.path("src/lib.zig"),
        .target = target,
        .optimize = optimize,
    });

    const demo = b.addExecutable(.{
        .name = "demo",
        .root_source_file = b.path("src/demo.zig"),
        .target = target,
        .optimize = optimize,
    });
    demo.root_module.addImport("zilp", lib);
    b.installArtifact(demo);

    const run = b.addRunArtifact(demo);
    if (b.args) |args| run.addArgs(args);

    const run_step = b.step("run", "Run the demo");
    run_step.dependOn(&run.step);
}
