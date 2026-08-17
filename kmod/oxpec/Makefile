# Out-of-tree oxpec. Same source builds on Bazzite and CachyOS
# against that machine's running kernel build tree.
obj-m += oxpec.o

KDIR ?= /lib/modules/$(KERNELRELEASE)/build
KERNELRELEASE ?= $(shell uname -r)

all:
	$(MAKE) -C $(KDIR) M=$(CURDIR) modules

clean:
	$(MAKE) -C $(KDIR) M=$(CURDIR) clean

.PHONY: all clean
