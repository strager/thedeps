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

/*
 * Command line arguments
 */
inline int OPT_command   = 1;
inline int OPT_follow    = 1;
inline int OPT_printid   = 1;
inline int OPT_trace     = 0;
inline string TRACE      = "";

dtrace:::BEGIN 
{
   /* globals */
   trackedpid[pid] = 0;
   self->child = 0;
   this->type = 0;
}

/*
 * Save syscall entry info
 */

/* MacOS X: notice first appearance of child from fork. Its parent
   fires syscall::*fork:return in the ususal way (see below) */
syscall:::entry
/OPT_follow && trackedpid[ppid] == -1 && 0 == self->child/
{
   /* set as child */
   self->child = 1;

   /* print output */
   self->code = errno == 0 ? "" : "Err#";
   /* OPT_printid  ? printf("%5d/%d:  ",pid,tid) : 1; */
   OPT_printid  ? printf("%5d/0x%x:  ",pid,tid) : 1;
   printf("%s()\t\t = %d %s%d\n","fork",
       0,self->code,(int)errno);
}

/* MacOS X: notice first appearance of child and parent from vfork */
syscall:::entry
/OPT_follow && trackedpid[ppid] > 0 && 0 == self->child/
{
   /* set as child */
   this->vforking_tid = trackedpid[ppid];
   self->child = (this->vforking_tid == tid) ? 0 : 1;

   /* print output */
   self->code = errno == 0 ? "" : "Err#";
   /* OPT_printid  ? printf("%5d/%d:  ",pid,tid) : 1; */
   OPT_printid  ? printf("%5d/0x%x:  ",(this->vforking_tid == tid) ? ppid : pid,tid) : 1;
   printf("%s()\t\t = %d %s%d\n","vfork",
       (this->vforking_tid == tid) ? pid : 0,self->code,(int)errno);
}

syscall:::entry
/(OPT_command && pid == $target) || 
 (self->child)/
{
   /* set start details */
   self->start = timestamp;
   self->vstart = vtimestamp;
   self->arg0 = arg0;
   self->arg1 = arg1;
   self->arg2 = arg2;
}

/* 5 and 6 arguments */
syscall::select:entry,
syscall::mmap:entry,
syscall::pwrite:entry,
syscall::pread:entry
/(OPT_command && pid == $target) || 
 (self->child)/
{
   self->arg3 = arg3;
   self->arg4 = arg4;
   self->arg5 = arg5;
}

/*
 * Follow children
 */
syscall::fork:entry
/OPT_follow && self->start/
{
   /* track this parent process */
   trackedpid[pid] = -1;
}

syscall::vfork:entry
/OPT_follow && self->start/
{
   /* track this parent process */
   trackedpid[pid] = tid;
}

/* syscall::rexit:entry */
syscall::exit:entry
{
   /* forget child */
   self->child = 0;
   trackedpid[pid] = 0;
}

/*
 * Check for syscall tracing
 */
syscall:::entry
/OPT_trace && probefunc != TRACE/
{
   /* drop info */
   self->start = 0;
   self->vstart = 0;
   self->arg0 = 0;
   self->arg1 = 0;
   self->arg2 = 0;
   self->arg3 = 0;
   self->arg4 = 0;
   self->arg5 = 0;
}

/*
 * Print return data
 */

/*
 * NOTE:
 *  The following code is written in an intentionally repetetive way.
 *  The first versions had no code redundancies, but performed badly during
 *  benchmarking. The priority here is speed, not cleverness. I know there
 *  are many obvious shortcuts to this code, Ive tried them. This style has
 *  shown in benchmarks to be the fastest (fewest probes, fewest actions).
 */

/* print 3 args, return as hex */
syscall::sigprocmask:return
/self->start/
{
   /* calculate elapsed time */
   this->elapsed = timestamp - self->start;
   self->start = 0;
   this->cpu = vtimestamp - self->vstart;
   self->vstart = 0;
   self->code = errno == 0 ? "" : "Err#";

   /* print optional fields */
   /* OPT_printid  ? printf("%5d/%d:  ",pid,tid) : 1; */
   OPT_printid  ? printf("%5d/0x%x:  ",pid,tid) : 1;

   /* print main data */
   printf("%s(0x%X, 0x%X, 0x%X)\t\t = 0x%X %s%d\n",probefunc,
       (int)self->arg0,self->arg1,self->arg2,(int)arg0,
       self->code,(int)errno);
   self->arg0 = 0;
   self->arg1 = 0;
   self->arg2 = 0;
}

/* print 3 args, arg0 as a string */
syscall::execve:return,
syscall::stat:return, 
syscall::stat64:return, 
syscall::lstat:return, 
syscall::lstat64:return, 
syscall::access:return,
syscall::mkdir:return,
syscall::chdir:return,
syscall::chroot:return,
syscall::getattrlist:return, /* XXX 5 arguments */
syscall::chown:return,
syscall::lchown:return,
syscall::chflags:return,
syscall::readlink:return,
syscall::utimes:return,
syscall::pathconf:return,
syscall::truncate:return,
syscall::getxattr:return,
syscall::setxattr:return,
syscall::removexattr:return,
syscall::unlink:return,
syscall::open:return,
syscall::open_nocancel:return
/self->start/
{
   /* calculate elapsed time */
   this->elapsed = timestamp - self->start;
   self->start = 0;
   this->cpu = vtimestamp - self->vstart;
   self->vstart = 0;
   self->code = errno == 0 ? "" : "Err#";

   /* print optional fields */
   /* OPT_printid  ? printf("%5d/%d:  ",pid,tid) : 1; */
   OPT_printid  ? printf("%5d/0x%x:  ",pid,tid) : 1;

   /* print main data */
   printf("%s(\"%S\", 0x%X, 0x%X)\t\t = %d %s%d\n",probefunc,
       copyinstr(self->arg0),self->arg1,self->arg2,(int)arg0,
       self->code,(int)errno);
   self->arg0 = 0;
   self->arg1 = 0;
   self->arg2 = 0;
}

/* print 3 args, arg1 as a string */
syscall::write:return,
syscall::write_nocancel:return,
syscall::read:return,
syscall::read_nocancel:return
/self->start/
{
   /* calculate elapsed time */
   this->elapsed = timestamp - self->start;
   self->start = 0;
   this->cpu = vtimestamp - self->vstart;
   self->vstart = 0;
   self->code = errno == 0 ? "" : "Err#";

   /* print optional fields */
   /* OPT_printid  ? printf("%5d/%d:  ",pid,tid) : 1; */
   OPT_printid  ? printf("%5d/0x%x:  ",pid,tid) : 1;

   /* print main data */
   printf("%s(0x%X, \"%S\", 0x%X)\t\t = %d %s%d\n",probefunc,self->arg0,
       arg0 == -1 ? "" : stringof(copyin(self->arg1,arg0)),self->arg2,(int)arg0,
       self->code,(int)errno);
   self->arg0 = 0;
   self->arg1 = 0;
   self->arg2 = 0;
}

/* print 2 args, arg0 and arg1 as strings */
syscall::rename:return,
syscall::symlink:return,
syscall::link:return
/self->start/
{
   /* calculate elapsed time */
   this->elapsed = timestamp - self->start;
   self->start = 0;
   this->cpu = vtimestamp - self->vstart;
   self->vstart = 0;
   self->code = errno == 0 ? "" : "Err#";

   /* print optional fields */
   /* OPT_printid  ? printf("%5d/%d:  ",pid,tid) : 1; */
   OPT_printid  ? printf("%5d/0x%x:  ",pid,tid) : 1;

   /* print main data */
   printf("%s(\"%S\", \"%S\")\t\t = %d %s%d\n",probefunc,
       copyinstr(self->arg0), copyinstr(self->arg1),
       (int)arg0,self->code,(int)errno);
   self->arg0 = 0;
   self->arg1 = 0;
   self->arg2 = 0;
}

/* print 0 arg output */
syscall::*fork:return
/self->start/
{
   /* calculate elapsed time */
   this->elapsed = timestamp - self->start;
   self->start = 0;
   this->cpu = vtimestamp - self->vstart;
   self->vstart = 0;
   self->code = errno == 0 ? "" : "Err#";

   /* print optional fields */
   /* OPT_printid  ? printf("%5d/%d:  ",pid,tid) : 1; */
   OPT_printid  ? printf("%5d/0x%x:  ",pid,tid) : 1;

   /* print main data */
   printf("%s()\t\t = %d %s%d\n",probefunc,
       (int)arg0,self->code,(int)errno);
   self->arg0 = 0;
   self->arg1 = 0;
   self->arg2 = 0;
}

/* print 1 arg output */
syscall::close:return,
syscall::close_nocancel:return
/self->start/
{
   /* calculate elapsed time */
   this->elapsed = timestamp - self->start;
   self->start = 0;
   this->cpu = vtimestamp - self->vstart;
   self->vstart = 0;
   self->code = errno == 0 ? "" : "Err#";

   /* print optional fields */
   /* OPT_printid  ? printf("%5d/%d:  ",pid,tid) : 1; */
   OPT_printid  ? printf("%5d/0x%x:  ",pid,tid) : 1;

   /* print main data */
   printf("%s(0x%X)\t\t = %d %s%d\n",probefunc,self->arg0,
       (int)arg0,self->code,(int)errno);
   self->arg0 = 0;
   self->arg1 = 0;
   self->arg2 = 0;
}

/* print 2 arg output */
syscall::utimes:return,
syscall::munmap:return
/self->start/
{
   /* calculate elapsed time */
   this->elapsed = timestamp - self->start;
   self->start = 0;
   this->cpu = vtimestamp - self->vstart;
   self->vstart = 0;
   self->code = errno == 0 ? "" : "Err#";

   /* print optional fields */
   /* OPT_printid  ? printf("%5d/%d:  ",pid,tid) : 1; */
   OPT_printid  ? printf("%5d/0x%x:  ",pid,tid) : 1;

   /* print main data */
   printf("%s(0x%X, 0x%X)\t\t = %d %s%d\n",probefunc,self->arg0,
       self->arg1,(int)arg0,self->code,(int)errno);
   self->arg0 = 0;
   self->arg1 = 0;
   self->arg2 = 0;
}

/* print pread/pwrite with 4 arguments */
syscall::pread*:return,
syscall::pwrite*:return
/self->start/
{
   /* calculate elapsed time */
   this->elapsed = timestamp - self->start;
   self->start = 0;
   this->cpu = vtimestamp - self->vstart;
   self->vstart = 0;
   self->code = errno == 0 ? "" : "Err#";

   /* print optional fields */
   /* OPT_printid  ? printf("%5d/%d:  ",pid,tid) : 1; */
   OPT_printid  ? printf("%5d/0x%x:  ",pid,tid) : 1;

   /* print main data */
   printf("%s(0x%X, \"%S\", 0x%X, 0x%X)\t\t = %d %s%d\n",probefunc,self->arg0,
       stringof(copyin(self->arg1,self->arg2)),self->arg2,self->arg3,(int)arg0,self->code,(int)errno);
   self->arg0 = 0;
   self->arg1 = 0;
   self->arg2 = 0;
   self->arg3 = 0;
}

/* print select with 5 arguments */
syscall::select:return
/self->start/
{
   /* calculate elapsed time */
   this->elapsed = timestamp - self->start;
   self->start = 0;
   this->cpu = vtimestamp - self->vstart;
   self->vstart = 0;
   self->code = errno == 0 ? "" : "Err#";

   /* print optional fields */
   /* OPT_printid  ? printf("%5d/%d:  ",pid,tid) : 1; */
   OPT_printid  ? printf("%5d/0x%x:  ",pid,tid) : 1;

   /* print main data */
   printf("%s(0x%X, 0x%X, 0x%X, 0x%X, 0x%X)\t\t = %d %s%d\n",probefunc,self->arg0,
       self->arg1,self->arg2,self->arg3,self->arg4,(int)arg0,self->code,(int)errno);
   self->arg0 = 0;
   self->arg1 = 0;
   self->arg2 = 0;
   self->arg3 = 0;
   self->arg4 = 0;
}

/* mmap has 6 arguments */
syscall::mmap:return
/self->start/
{
   /* calculate elapsed time */
   this->elapsed = timestamp - self->start;
   self->start = 0;
   this->cpu = vtimestamp - self->vstart;
   self->vstart = 0;
   self->code = errno == 0 ? "" : "Err#";

   /* print optional fields */
   /* OPT_printid  ? printf("%5d/%d:  ",pid,tid) : 1; */
   OPT_printid  ? printf("%5d/0x%x:  ",pid,tid) : 1;

   /* print main data */
   printf("%s(0x%X, 0x%X, 0x%X, 0x%X, 0x%X, 0x%X)\t\t = 0x%X %s%d\n",probefunc,self->arg0,
       self->arg1,self->arg2,self->arg3,self->arg4,self->arg5, (int)arg0,self->code,(int)errno);
   self->arg0 = 0;
   self->arg1 = 0;
   self->arg2 = 0;
   self->arg3 = 0;
   self->arg4 = 0;
   self->arg5 = 0;
}

/* print 3 arg output - default */
syscall:::return
/self->start/
{
   /* calculate elapsed time */
   this->elapsed = timestamp - self->start;
   self->start = 0;
   this->cpu = vtimestamp - self->vstart;
   self->vstart = 0;
   self->code = errno == 0 ? "" : "Err#";

   /* print optional fields */
   /* OPT_printid  ? printf("%5d/%d:  ",pid,tid) : 1; */
   OPT_printid  ? printf("%5d/0x%x:  ",pid,tid) : 1;

   /* print main data */
   printf("%s(0x%X, 0x%X, 0x%X)\t\t = %d %s%d\n",probefunc,self->arg0,
       self->arg1,self->arg2,(int)arg0,self->code,(int)errno);
   self->arg0 = 0;
   self->arg1 = 0;
   self->arg2 = 0;
}
