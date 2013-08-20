#!/usr/bin/env perl

use strict;
use warnings;

# key=value, where value is a number or string.
# Puts key in first capture group; value in second.
my $arg_re = qr/
    ([a-z]+)
    =
    ( \d+ | "(?:.*?)(?!\\)" )
/x;

my $arg_in_list_re = qr/
    # FIXME(strager): Not 100% accurate.  Allows trailing
    # commas.
    ${arg_re}
    (?:,\s+)?
/x;

# [pid] syscall(args) = ret
my $syscall_re = qr/^
    \[(?<pid>\d+)\]\s*
    (?<is_unknown>\?)?
    (?<name>[^( ]*)
    (?:\( (?<arguments> (?:${arg_in_list_re})* )\))?
    (?:\ =\ (?<return_value>-?\d+))?
/x;

my %fds = ();
my %files_touched = ();

while (<>) {
    # Parse syscall lines.
    if ($_ =~ $syscall_re) {
        my $pid = $+{pid};
        my $is_unknown = $+{is_unknown};
        my $name = $+{name};
        my $raw_arguments = $+{arguments};
        my $return_value = $+{return_value};

        if (defined($raw_arguments)) {
            my %arguments = ();
            while ($raw_arguments =~ /${arg_in_list_re}/xg) {
                # TODO Unescape strings and all that.
                $arguments{$1} = $2;
            }

            if (defined($arguments{fd}) and defined($arguments{path})) {
                $fds{$arguments{fd}} = $arguments{path};
            } elsif (defined($arguments{open}) and defined($arguments{path})) {
                $fds{$return_value} = $arguments{path};
            }

            if (defined($arguments{path})) {
                $files_touched{$arguments{path}} = 1;
            }
            if (defined($arguments{frompath})) {
                $files_touched{$arguments{frompath}} = 1;
            }
            if (defined($arguments{topath})) {
                $files_touched{$arguments{topath}} = 1;
            }
            if (defined($arguments{fd})) {
                my $fd = $arguments{fd};
                if ($fd == 0 or $fd == 1 or $fd == 2) {
                    # stdin, stdout, stderr
                } elsif (defined($fds{$fd})) {
                    $files_touched{$fds{$fd}} = 1;
                } else {
                    print "Warning: No file path known for file descriptor $fd\n";
                }
            }
        }
    }
}

my $num_files_touched = keys %files_touched;
print "Touched $num_files_touched file(s):\n";
for (keys %files_touched) {
    print " - $_\n";
}
