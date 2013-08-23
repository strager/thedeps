#!/usr/bin/env perl

use strict;
use warnings;

# Prefix all warnings with "Warning: ".
BEGIN {
    $SIG{'__WARN__'} = sub {
        warn "Warning: ", $_[0];
    }
}

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
\n$/x;

my $string_body_re = qr/^"(.*)\\0"$/;

my $string_escape_re = qr/
    \\ (?:
        ([0-3][0-7]{2}) # Three octal digits.
        | ([^0-9])      # Non-digit literal character.
    )
/x;

sub parse_value ($) {
    my $v = shift;
    if ($v =~ $string_body_re) {
        ($v = $1) =~ s/$string_escape_re/
            if (defined $1) {
                chr oct $1;
            } elsif (defined $2) {
                $2;
            } else {
                die "Broken \$string_escape_re regex";
            }
        /eg;
    }
    return $v;
}

sub parse_syscall ($) {
    $_ = shift;
    return undef unless /$syscall_re/;

    my $is_unknown = $+{is_unknown};
    my $name = $+{name};
    my $pid = $+{pid};
    my $raw_arguments = $+{arguments};
    my $return_value = $+{return_value};

    my %arguments = ();
    if (defined $raw_arguments) {
        while ($raw_arguments =~ /${arg_in_list_re}/xg) {
            $arguments{$1} = parse_value($2);
        }
    }

    return {
        arguments => \%arguments,
        is_unknown => defined $is_unknown,
        name => $name,
        pid => $pid,
        return_value => $return_value
    };
}

my %fds = ();
my %files_touched = ();

while (<>) {
    my $syscall_ref = parse_syscall($_);
    if (!$syscall_ref) {
        warn "Failed to parse line: $_" unless $_ eq "\n";
        next;
    }

    my %syscall = %{$syscall_ref};
    my %args = %{$syscall{arguments}};

    warn "Unknown syscall: $syscall{name}" if $syscall{is_unknown};

    if (exists $args{fd} and exists $args{path}) {
        $fds{$args{fd}} = $args{path};
    } elsif (exists $args{open} and exists $args{path}) {
        $fds{$syscall{return_value}} = $args{path};
    }

    if (exists $args{path}) {
        $files_touched{$args{path}} = 1;
    }
    if (exists $args{frompath}) {
        $files_touched{$args{frompath}} = 1;
    }
    if (exists $args{topath}) {
        $files_touched{$args{topath}} = 1;
    }
    if (exists $args{fd}) {
        my $fd = $args{fd};
        if ($fd == 0 or $fd == 1 or $fd == 2) {
            # stdin, stdout, stderr
        } elsif (exists $fds{$fd}) {
            $files_touched{$fds{$fd}} = 1;
        } else {
            warn "No file path known for file descriptor $fd";
        }
    }
}

my $num_files_touched = keys %files_touched;
print "Touched $num_files_touched files:\n";
for (sort keys %files_touched) {
    my $v = parse_value($_);
    print " - $v\n";
}
