//! Linux `/proc/self/stat` parser (host-only tooling). Kept under `src/utils/` so it does not land in the wasm `usim` graph; import this file explicitly where needed.
const std = @import("std");

pub const ProcState = enum {
    /// Running
    R,
    /// Sleeping in an interruptible wait
    S,
    /// Waiting in uninterruptible disk sleep
    D,
    /// Zombie
    Z,
    /// Stopped (on a signal) or (before Linux 2.6.33) trace stopped
    T,
    /// Tracing stop (Linux 2.6.33 onward)
    t,
    /// Paging (only before Linux 2.6.0) or Waking (Linux 2.6.33 to 3.13 only)
    W,
    /// Dead (from Linux 2.6.0 onward)
    X,
    /// Dead (Linux 2.6.33 to 3.13 only)
    x,
    /// Wakekill (Linux 2.6.33 to 3.13 only)
    K,
    /// Parked (Linux 3.9 to 3.13 only)
    P,
    /// Idle (Linux 4.14 onward)
    I,
};

/// The fields, in order, with their proper [scanf(3)](https://man7.org/linux/man-pages/man3/scanf.3.html)
/// format specifiers, are listed below. \
/// Whether or not certain of
/// these fields display valid information is governed by a
/// ptrace access mode `PTRACE_MODE_READ_FSCREDS` | `PTRACE_MODE_NOAUDIT` check
/// (refer to [ptrace(2)](https://man7.org/linux/man-pages/man2/ptrace.2.html)). \
/// If the check denies access, then the field value is displayed as 0.
/// The affected fields are indicated with the marking [PT].
pub const ProcStat = struct {
    /// `%d`
    pid: std.c.pid_t,
    /// `%s`
    comm: []const u8,
    /// `%c`
    state: ProcState,
    /// `%d`
    ppid: std.c.pid_t,
    /// `%d`
    pgrp: std.c_int,
    /// `%d`
    session: std.c_int,
    /// `%d`
    tty_nr: std.c_int,
    /// `%d`
    tpgid: std.c_int,
    /// `%u`
    flags: std.c_uint,
    /// `%lu`
    minflt: std.c_ulong,
    /// `%lu`
    cminflt: std.c_ulong,
    /// `%lu`
    majflt: std.c_ulong,
    /// `%lu`
    cmajflt: std.c_ulong,
    /// `%lu`
    utime: std.c_ulong,
    /// `%lu`
    stime: std.c_ulong,
    /// `%ld`
    cutime: std.c_long,
    /// `%ld`
    cstime: std.c_long,
    /// `%ld`
    priority: std.c_long,
    /// `%ld`
    nice: std.c_long,
    /// `%ld`
    num_threads: std.c_long,
    /// `%ld`
    itrealvalue: std.c_long,
    /// `%llu`
    starttime: std.c_ulonglong,
    /// `%lu`
    vsize: std.c_ulong,
    /// `%ld`
    rss: std.c_long,
    /// `%lu`
    rsslim: std.c_ulong,
    /// `%lu`
    startcode: std.c_ulong,
    /// `%lu`
    endcode: std.c_ulong,
    /// `%lu`
    startstack: std.c_ulong,
    /// `%lu`
    kstkesp: std.c_ulong,
    /// `%lu`
    kstkeip: std.c_ulong,
    /// `%lu`
    signal: std.c_ulong,
    /// `%lu`
    blocked: std.c_ulong,
    /// `%lu`
    sigignore: std.c_ulong,
    /// `%lu`
    sigcatch: std.c_ulong,
    /// `%lu`
    wchan: std.c_ulong,
    /// `%lu`
    nswap: std.c_ulong,
    /// `%lu`
    cnswap: std.c_ulong,
    /// `%d`
    exit_signal: std.c_int,
    /// `%d`
    processor: std.c_int,
    /// `%u`
    rt_priority: std.c_uint,
    /// `%u`
    policy: std.c_uint,
    /// `%llu`
    delayacct_blkio_ticks: std.c_ulonglong,
    /// `%lu`
    guest_time: std.c_ulong,
    /// `%ld`
    cguest_time: std.c_long,
    /// `%lu`
    start_data: std.c_ulong,
    /// `%lu`
    end_data: std.c_ulong,
    /// `%lu`
    start_brk: std.c_ulong,
    /// `%lu`
    arg_start: std.c_ulong,
    /// `%lu`
    arg_end: std.c_ulong,
    /// `%lu`
    env_start: std.c_ulong,
    /// `%lu`
    env_end: std.c_ulong,
    /// `%d`
    exit_code: std.c_int,
};

/// From the Linux Man Pages: [proc_pid_stat(5) — Linux manual page](https://man7.org/linux/man-pages/man5/proc_pid_stat.5.html) \
/// From the Linux Kernel Docs: https://git.kernel.org/pub/scm/linux/kernel/git/stable/linux.git/tree/Documentation/filesystems/proc.rst#n329
///
/// [`/proc/pid/stat`](https://man7.org/linux/man-pages/man5/proc_pid_stat.5.html)
///
/// Status information about the process.  This is used by
/// [ps(1)](https://man7.org/linux/man-pages/man1/ps.1.html).
/// It is defined in the kernel source file `fs/proc/array.c`.
pub fn stat(buf: []u8) !ProcStat {
    const stat_fd = try std.posix.open("/proc/self/stat", std.posix.O{ .ACCMODE = .RDONLY }, std.c.S.IRUSR);
    defer std.posix.close(stat_fd);
    const len = try std.posix.read(stat_fd, buf);
    var seq = std.mem.splitScalar(u8, buf[0..len], ' ');
    var proc_stat: ProcStat = undefined;
    inline for (std.meta.fields(ProcStat)) |field| {
        const seq_item = seq.next() orelse break;
        @field(proc_stat, field.name) = switch (field.type) {
            ProcState => std.meta.stringToEnum(ProcState, seq_item) orelse unreachable,
            []const u8 => seq_item,
            else => std.fmt.parseInt(field.type, seq_item, 0) catch 0,
        };
    }
    return proc_stat;
}
