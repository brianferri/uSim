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

pub const ProcStat = struct {
    pid: std.c.pid_t,
    comm: []const u8,
    state: ProcState,
    ppid: std.c.pid_t,
    pgrp: c_int,
    session: c_int,
    tty_nr: c_int,
    tpgid: c_int,
    flags: c_uint,
    minflt: c_ulong,
    cminflt: c_ulong,
    majflt: c_ulong,
    cmajflt: c_ulong,
    utime: c_ulong,
    stime: c_ulong,
    cutime: c_long,
    cstime: c_long,
    priority: c_long,
    nice: c_long,
    num_threads: c_long,
    itrealvalue: c_long,
    starttime: c_ulonglong,
    vsize: c_ulong,
    rss: c_long,
    rsslim: c_ulong,
    startcode: c_ulong,
    endcode: c_ulong,
    startstack: c_ulong,
    kstkesp: c_ulong,
    kstkeip: c_ulong,
    signal: c_ulong,
    blocked: c_ulong,
    sigignore: c_ulong,
    sigcatch: c_ulong,
    wchan: c_ulong,
    nswap: c_ulong,
    cnswap: c_ulong,
    exit_signal: c_int,
    processor: c_int,
    rt_priority: c_uint,
    policy: c_uint,
    delayacct_blkio_ticks: c_ulonglong,
    guest_time: c_ulong,
    cguest_time: c_long,
    start_data: c_ulong,
    end_data: c_ulong,
    start_brk: c_ulong,
    arg_start: c_ulong,
    arg_end: c_ulong,
    env_start: c_ulong,
    env_end: c_ulong,
    exit_code: c_int,
};

/// From the Linux Man Pages: [proc_pid_stat(5) — Linux manual page](https://man7.org/linux/man-pages/man5/proc_pid_stat.5.html)
/// From the Linux Kernel Docs: https://git.kernel.org/pub/scm/linux/kernel/git/stable/linux.git/tree/Documentation/filesystems/proc.rst#n329
///
/// [`/proc/pid/stat`](https://man7.org/linux/man-pages/man5/proc_pid_stat.5.html)
///
/// Status information about the process.  This is used by
/// [ps(1)](https://man7.org/linux/man-pages/man1/ps.1.html).
/// It is defined in the kernel source file `fs/proc/array.c`.
///
/// The fields, in order, with their proper [scanf(3)](https://man7.org/linux/man-pages/man3/scanf.3.html)
/// format specifiers, are listed below. Whether or not certain of
/// these fields display valid information is governed by a
/// ptrace access mode `PTRACE_MODE_READ_FSCREDS` | `PTRACE_MODE_NOAUDIT` check
/// (refer to [ptrace(2)](https://man7.org/linux/man-pages/man2/ptrace.2.html)).
/// If the check denies access, then the field value is displayed as 0.
/// The affected fields are indicated with the marking [PT].
pub fn stat(buf: []u8) !ProcStat {
    const stat_fd = try std.posix.open("/proc/self/stat", std.posix.O{ .ACCMODE = .RDONLY }, std.c.S.IRUSR);
    defer std.posix.close(stat_fd);
    const len = try std.posix.read(stat_fd, buf);
    var seq = std.mem.splitScalar(u8, buf[0..len], ' ');
    var procStat: ProcStat = undefined;
    inline for (std.meta.fields(ProcStat)) |field| {
        const seqItem = seq.next() orelse break;
        @field(procStat, field.name) = switch (field.type) {
            ProcState => std.meta.stringToEnum(ProcState, seqItem) orelse unreachable,
            []const u8 => seqItem,
            else => std.fmt.parseInt(field.type, seqItem, 0) catch 0,
        };
    }
    return procStat;
}
