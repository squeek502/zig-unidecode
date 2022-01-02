const std = @import("std");

pub fn build(b: *std.build.Builder) void {
    const mode = b.standardReleaseOptions();

    const lib = b.addStaticLibrary("unidecode", "src/unidecode.zig");
    lib.setBuildMode(mode);
    lib.install();

    const main_tests = b.addTest("src/unidecode.zig");
    main_tests.setBuildMode(mode);

    const test_step = b.step("test", "Run unidecode tests");
    test_step.dependOn(&main_tests.step);
}
