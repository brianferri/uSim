const std = @import("std");

const ProcState = enum {
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
const ProcStat = struct {
    /// `%d`
    pid: std.c.pid_t,
    /// `%s`
    comm: []const u8,
    /// `%c`
    state: ProcState,
    /// `%d`
    ppid: std.c.pid_t,
    /// `%d`
    pgrp: c_int,
    /// `%d`
    session: c_int,
    /// `%d`
    tty_nr: c_int,
    /// `%d`
    tpgid: c_int,
    /// `%u`
    flags: c_uint,
    /// `%lu`
    minflt: c_ulong,
    /// `%lu`
    cminflt: c_ulong,
    /// `%lu`
    majflt: c_ulong,
    /// `%lu`
    cmajflt: c_ulong,
    /// `%lu`
    utime: c_ulong,
    /// `%lu`
    stime: c_ulong,
    /// `%ld`
    cutime: c_long,
    /// `%ld`
    cstime: c_long,
    /// `%ld`
    priority: c_long,
    /// `%ld`
    nice: c_long,
    /// `%ld`
    num_threads: c_long,
    /// `%ld`
    itrealvalue: c_long,
    /// `%llu`
    starttime: c_ulonglong,
    /// `%lu`
    vsize: c_ulong,
    /// `%ld`
    rss: c_long,
    /// `%lu`
    rsslim: c_ulong,
    /// `%lu`
    startcode: c_ulong,
    /// `%lu`
    endcode: c_ulong,
    /// `%lu`
    startstack: c_ulong,
    /// `%lu`
    kstkesp: c_ulong,
    /// `%lu`
    kstkeip: c_ulong,
    /// `%lu`
    signal: c_ulong,
    /// `%lu`
    blocked: c_ulong,
    /// `%lu`
    sigignore: c_ulong,
    /// `%lu`
    sigcatch: c_ulong,
    /// `%lu`
    wchan: c_ulong,
    /// `%lu`
    nswap: c_ulong,
    /// `%lu`
    cnswap: c_ulong,
    /// `%d`
    exit_signal: c_int,
    /// `%d`
    processor: c_int,
    /// `%u`
    rt_priority: c_uint,
    /// `%u`
    policy: c_uint,
    /// `%llu`
    delayacct_blkio_ticks: c_ulonglong,
    /// `%lu`
    guest_time: c_ulong,
    /// `%ld`
    cguest_time: c_long,
    /// `%lu`
    start_data: c_ulong,
    /// `%lu`
    end_data: c_ulong,
    /// `%lu`
    start_brk: c_ulong,
    /// `%lu`
    arg_start: c_ulong,
    /// `%lu`
    arg_end: c_ulong,
    /// `%lu`
    env_start: c_ulong,
    /// `%lu`
    env_end: c_ulong,
    /// `%d`
    exit_code: c_int,
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
