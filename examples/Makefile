CFILES := $(wildcard *.c)
EXEFILES := $(CFILES:.c=)

all: $(EXEFILES)

%: %.c
	$(CC) -o $@ $<
