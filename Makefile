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

# ---- Windows build (x86-64, cross-built: NASM -f win64 here, the C platform layer and the link in a mingw
# docker image; see win/README.md) --------------------------------------------------------------------
DOCKER_MINGW := docker run --rm -u $$(id -u):$$(id -g) -v $(CURDIR):/src -w /src ac-mingw
WINC := x86_64-w64-mingw32-gcc
WINOBJS := $(patsubst src/%.asm,build/win/%.o,$(SRCS))
WINCSRCS := $(wildcard win/*.c)
WINCOBJS := $(patsubst win/%.c,build/win/c_%.o,$(WINCSRCS))
windows: build/win/assemblycraft.exe
build/win/assemblycraft.exe: $(WINOBJS) build/win/syscall_stub.o $(WINCOBJS)
	$(DOCKER_MINGW) $(WINC) -o $@ $(WINOBJS) build/win/syscall_stub.o $(WINCOBJS) -Lwin/glfw/lib -lglfw3 \
	  -lopengl32 -lgdi32 -lwinmm -lws2_32 -lbcrypt -static -Wl,--image-base=0x400000 -Wl,--disable-dynamicbase \
	  -Wl,--disable-high-entropy-va -Xlinker --stack -Xlinker 8388608,8388608
build/win/%.o: src/%.asm $(INCS) | build/win ; nasm -f win64 -DWIN64 --gprefix w_ -Isrc/ $< -o $@
build/win/syscall_stub.o: win/syscall_stub.asm | build/win ; nasm -f win64 $< -o $@
build/win/c_%.o: win/%.c win/win.h | build/win ; $(DOCKER_MINGW) $(WINC) -O2 -std=gnu11 -Wall -Wextra -Iwin/glfw/include -c $< -o $@
build/win: ; mkdir -p build/win
windows-image: ; docker build -t ac-mingw win
windows-zip: build/win/assemblycraft.exe
	rm -rf build/win/pkg && mkdir -p build/win/pkg/AssemblyCraft && cp build/win/assemblycraft.exe build/win/pkg/AssemblyCraft/ && cp win/README-WINDOWS.txt win/THIRD-PARTY.txt build/win/pkg/AssemblyCraft/ && cd build/win/pkg && zip -qr ../AssemblyCraft-0.13.0-win64.zip AssemblyCraft
.PHONY: all test run clean relay windows windows-image windows-zip
