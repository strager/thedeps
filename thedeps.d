/*
 * Original program header:
 *
 * dtruss - print process system call time details.
 *          Written using DTrace (Solaris 10 3/05).
 *
 * 17-Jun-2005, ver 0.80         (check for newer versions)
 *
 * USAGE: dtruss [-acdeflhoLs] [-t syscall] { -p PID | -n name | command }
 *
 *          -p PID          # examine this PID
 *          -n name         # examine this process name
 *          -t syscall      # examine this syscall only
 *          -a              # print all details
 *          -c              # print system call counts
 *          -d              # print relative timestamps (us)
 *          -e              # print elapsed times (us)
 *          -f              # follow children as they are forked
 *          -l              # force printing of pid/lwpid per line
 *          -o              # print on cpu times (us)
 *          -s              # print stack backtraces
 *          -L              # don't print pid/lwpid per line
 *          -b bufsize      # dynamic variable buf size (default is "4m")
 *  eg,
 *       dtruss df -h       # run and examine the "df -h" command
 *       dtruss -p 1871     # examine PID 1871
 *       dtruss -n tar      # examine all processes called "tar"
 *       dtruss -f test.sh  # run test.sh and follow children
 *
 * The elapsed times are interesting, to help identify syscalls that take
 *  some time to complete (during which the process may have context
 *  switched off the CPU). 
 *
 * SEE ALSO: procsystime    # DTraceToolkit
 *           dapptrace      # DTraceToolkit
 *           truss
 *
 * COPYRIGHT: Copyright (c) 2005 Brendan Gregg.
 *
 * CDDL HEADER START
 *
 *  The contents of this file are subject to the terms of the
 *  Common Development and Distribution License, Version 1.0 only
 *  (the "License").  You may not use this file except in compliance
 *  with the License.
 *
 *  You can obtain a copy of the license at Docs/cddl1.txt
 *  or http://www.opensolaris.org/os/licensing.
 *  See the License for the specific language governing permissions
 *  and limitations under the License.
 *
 * CDDL HEADER END
 *
 * Author: Brendan Gregg  [Sydney, Australia]
 *
 * TODO: Track signals, more output formatting.
 *
 * 29-Apr-2005   Brendan Gregg   Created this.
 * 09-May-2005      "      " 	Fixed evaltime (thanks Adam L.)
 * 16-May-2005	   "      "	Added -t syscall tracing.
 * 17-Jun-2005	   "      "	Added -s stack backtraces.
 */

#pragma D option quiet

dtrace:::BEGIN 
{
    /* globals */
    trackedpid[pid] = 0;
    self->child = 0;
    this->type = 0;
}

/*
 * MacOS X: notice first appearance of child from fork. Its
 * parent fires syscall::*fork:return in the ususal way (see
 * below).
 */
syscall:::entry
/trackedpid[ppid] == -1 && 0 == self->child/
{
    self->child = 1;
}

/*
 * MacOS X: notice first appearance of child and parent from
 * vfork
 */
syscall:::entry
/trackedpid[ppid] > 0 && 0 == self->child/
{
    this->vforking_tid = trackedpid[ppid];
    self->child = (this->vforking_tid == tid) ? 0 : 1;
}

syscall:::entry
/pid == $target || self->child/
{
    self->start = 1;
    self->arg0 = arg0;
    self->arg1 = arg1;
    self->arg2 = arg2;
}

syscall::select:entry,
syscall::mmap:entry,
syscall::pwrite:entry,
syscall::pread:entry
/pid == $target || self->child/
{
    self->arg3 = arg3;
    self->arg4 = arg4;
    self->arg5 = arg5;
}

/*
 * Follow forked children.
 */
syscall::fork:entry
/self->start/
{
    /* Track this parent process. */
    trackedpid[pid] = -1;
}

/*
 * Follow vforked children.
 */
syscall::vfork:entry
/self->start/
{
    /* Track this parent process. */
    trackedpid[pid] = tid;
}

/*syscall::rexit:entry*/
syscall::exit:entry
{
    self->child = 0;
    trackedpid[pid] = 0;
}

/*
 * No important arguments, return value is important.
 */
syscall::getegid:return,
syscall::geteuid:return,
syscall::issetugid:return
/self->start/
{
	 self->start = 0;
	 printf("[%d] %s() = %d\n",
		  pid,
		  probefunc,
		  (int)arg0);
}

/*
 * First argument is a file path.
 */
syscall::access:return,
syscall::chdir:return,
syscall::chflags:return,
syscall::chown:return,
syscall::chroot:return,
syscall::execve:return,
syscall::getattrlist:return,
syscall::getxattr:return,
syscall::lchown:return,
syscall::lstat64:return, 
syscall::lstat:return, 
syscall::mkdir:return,
syscall::readlink:return,
syscall::removexattr:return,
syscall::setxattr:return,
syscall::stat64:return, 
syscall::stat:return, 
syscall::truncate:return,
syscall::unlink:return,
syscall::utimes:return
/self->start/
{
    self->start = 0;
    printf("[%d] %s(path=\"%S\")\n",
		  pid,
		  probefunc,
        copyinstr(self->arg0));
}

/*
 * First argument is a file descriptor.  Second argument is
 * an open(2) mode.  Return value is important.
 */
syscall::open:return,
syscall::open_nocancel:return
/self->start/
{
	 self->start = 0;
	 printf("[%d] %s(path=\"%S\", open=%d) = %d\n",
		  pid,
		  probefunc,
		  copyinstr(self->arg0),
		  self->arg1,
		  (int)arg0);
}

/*
 * First argument is a file descriptor.
 */
syscall::close:return,
syscall::close_nocancel:return,
syscall::fstat64:return,
syscall::fstat:return,
syscall::futimes:return,
syscall::pread*:return,
syscall::pwrite*:return,
syscall::read:return,
syscall::read_nocancel:return,
syscall::write:return,
syscall::write_nocancel:return
/self->start/
{
    self->start = 0;
    printf("[%d] %s(fd=%d)\n",
		  pid,
		  probefunc,
		  self->arg0);
}

/*
 * First and second arguments are file paths.
 */
syscall::link:return,
syscall::rename:return,
syscall::symlink:return
/self->start/
{
	 self->start = 0;
    printf("[%d] %s(frompath=\"%S\", topath\"%S\")\n",
		  pid,
		  probefunc,
		  copyinstr(self->arg0),
		  copyinstr(self->arg1));
}

/*
 * Third argument is a file descriptor.
 */
syscall::mmap:return /* Yes, fd is arg2! */
/self->start/
{
	 self->start = 0;
	 printf("[%d] %s(fd=%d)\n",
		  pid,
		  probefunc,
		  self->arg2);
}

/*
 * Boring syscalls.
 */
syscall::getpid:return,
syscall::mprotect:return,
syscall::munmap:return,
syscall::setegid:return,
syscall::seteuid:return,
syscall::setgid:return,
syscall::setuid:return,
syscall::sigprocmask:return,
syscall::thread_selfid:return
/self->start/
{
	 self->start = 0;
}

/*
 * Catch-all, printing a warning because we haven't handled
 * this syscall yet.
 */
syscall:::return
/self->start/
{
	 self->start = 0;
	 printf("[%d] ?%s\n",
		  pid,
		  probefunc);
}
