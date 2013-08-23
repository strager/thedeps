# thedeps

thedeps finds the[1] dependencies ("deps") of an execution,
including what files were read and what directories were
scanned.

[1] Only a reasonable subset.  For example, CPU architecture
and cache misses are not tracked, but may affect runtime
checks, concurrency, etc.

## Usage

### Mac OS X

Trace a program execution:

    # Traces `ls -la`; runs `sudo` for you (if needed).
    ./thedeps.osx ls -la

Analyze:

    # Prints files read from, written to, directories
    # scanned, etc.
    ./analyze.pl /var/folders/cf/y9hqh02n24n6slnznybgdk700000gn/T/thedeps.6441.CpCOX993

### Linux

Not supported.

### Windows

Not supported.
