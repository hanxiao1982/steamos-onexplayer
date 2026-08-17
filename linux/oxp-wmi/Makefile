# Out-of-tree build: make -C /lib/modules/$(uname -r)/build M=$PWD
# In-tree: obj-$(CONFIG_OXP_WMI) += oxp-wmi.o

obj-m += oxp-wmi.o

KDIR ?= /lib/modules/$(shell uname -r)/build
PWD  := $(shell pwd)

all:
	$(MAKE) -C $(KDIR) M=$(PWD) modules

clean:
	$(MAKE) -C $(KDIR) M=$(PWD) clean

.PHONY: all clean
