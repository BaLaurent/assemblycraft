NASMFLAGS := -f elf64 -g -F dwarf -Isrc/
SRCS := $(wildcard src/*.asm)
OBJS := $(patsubst src/%.asm,build/%.o,$(SRCS))
INCS := $(wildcard src/*.inc)
all: build/assemblycraft
build/assemblycraft: $(OBJS) ; gcc -no-pie -o $@ $(OBJS) -lglfw -lGL
build/%.o: src/%.asm $(INCS) | build ; nasm $(NASMFLAGS) $< -o $@
build: ; mkdir -p build
test: build/assemblycraft ; ./build/assemblycraft --selftest
run: build/assemblycraft ; ./build/assemblycraft
clean: ; rm -rf build
.PHONY: all test run clean
