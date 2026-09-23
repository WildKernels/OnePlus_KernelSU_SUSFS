CC ?= cc
CFLAGS ?= -Wall -Werror -O2
NQ_NCI_DEV ?= /dev/nq-nci
TARGET := nci_raw_tool

CPPFLAGS += -DNQ_NCI_DEV='"$(NQ_NCI_DEV)"'

all: $(TARGET)

$(TARGET): nci_raw_tool.c
	$(CC) $(CPPFLAGS) $(CFLAGS) -o $@ $<

clean:
	rm -f $(TARGET)

.PHONY: all clean
