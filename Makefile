NASMFLAGS := -f elf64 -g -F dwarf -Isrc/
SRCS := $(wildcard src/*.asm)
OBJS := $(patsubst src/%.asm,build/%.o,$(SRCS))
INCS := $(wildcard src/*.inc)
all: build/assemblycraft
build/assemblycraft: $(OBJS) ; gcc -no-pie -pthread -o $@ $(OBJS) -lglfw -lGL -lpulse-simple
build/%.o: src/%.asm $(INCS) | build ; nasm $(NASMFLAGS) $< -o $@
build: ; mkdir -p build
test: build/assemblycraft ; ./build/assemblycraft --selftest
run: build/assemblycraft ; ./build/assemblycraft
clean: ; rm -rf build
relay: | build ; nasm $(NASMFLAGS) server/acrelay.asm -o build/acrelay.o && ld -static -o build/acrelay build/acrelay.o
.PHONY: all test run clean relay
