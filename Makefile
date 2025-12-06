UNAME_M := $(shell uname -m)

ifeq ($(UNAME_M),x86_64)
    RUN_CMD = qemu-aarch64 -L /usr/aarch64-linux-gnu ./zig-out/bin/bme688_sensor
    TEST_CMD = qemu-aarch64 -L /usr/aarch64-linux-gnu zig-out/bin/bme688_sensor --test
else ifeq ($(UNAME_M),aarch64)
    RUN_CMD = ./zig-out/bin/bme688_sensor
    TEST_CMD = zig-out/bin/bme688_sensor --test
else
    $(error Unsupported arch: $(UNAME_M))
endif

.PHONY: build run test clean

build:
	@zig build

run: build
	@$(RUN_CMD)

test: build
	@zig test src/test.zig

clean:
	@rm -rf zig-out .zig-cache

