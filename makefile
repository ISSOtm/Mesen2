#Welcome to what must be the most terrible makefile ever (but hey, it works)
#Both clang & gcc work fine - clang seems to output faster code
#.NET 6 (and its dev tools) must be installed to compile the UI.
#The emulation core also requires SDL2.
#Run "make" to build, "make run" to run

MESENFLAGS=

ifeq ($(USE_GCC),true)
	CXX := g++
	CC := gcc
	AR := gcc-ar
	PROFILE_GEN_FLAG := -fprofile-generate
	PROFILE_USE_FLAG := -fprofile-use
else
	CXX := clang++
	CC := clang
	AR := llvm-ar
	PROFILE_GEN_FLAG := -fprofile-instr-generate=$(CURDIR)/PGOHelper/pgo.profraw
	PROFILE_USE_FLAG := -fprofile-instr-use=$(CURDIR)/PGOHelper/pgo.profdata
endif

SDL2LIB := $(shell sdl2-config --libs)
SDL2INC := $(shell sdl2-config --cflags)

LINKCHECKUNRESOLVED := -Wl,-z,defs

LINKOPTIONS :=
MESENOS :=
UNAME_S := $(shell uname -s)

ifeq ($(UNAME_S),Linux)
	MESENOS := linux
	SHAREDLIB := MesenCore.so
	STATICLIB := MesenCore.a
endif

ifeq ($(UNAME_S),Darwin)
	MESENOS := osx
	SHAREDLIB := MesenCore.dylib
	STATICLIB := MesenCore.a
	LTO := false
	STATICLINK := false
	LINKCHECKUNRESOLVED :=
endif

MACHINE := $(shell uname -m)
ifeq ($(MACHINE),x86_64)
	MESENPLATFORM := $(MESENOS)-x64
endif
ifneq ($(filter %86,$(MACHINE)),)
	MESENPLATFORM := $(MESENOS)-x64
endif
# TODO: this returns `aarch64` on one of my machines...
ifneq ($(filter arm%,$(MACHINE)),)
	MESENPLATFORM := $(MESENOS)-arm64
endif

MESENFLAGS += -m64

DEBUG ?= 0

ifeq ($(DEBUG),0)
	MESENFLAGS += -O3
	ifneq ($(LTO),false)
		MESENFLAGS += -DHAVE_LTO
		ifneq ($(USE_GCC),true)
			MESENFLAGS += -flto=thin
		else
			MESENFLAGS += -flto=auto
		endif
	endif
else
	MESENFLAGS += -O0 -g
	# Note: if compiling with a sanitizer, you will likely need to `LD_PRELOAD` the library `libMesenCore.so` will be linked against.
	ifneq ($(SANITIZER),)
		ifeq ($(SANITIZER),address)
			# Currently, `-fsanitize=address` is not supported together with `-fsanitize=thread`
			MESENFLAGS += -fsanitize=address
		else ifeq ($(SANITIZER),thread)
			# Currently, `-fsanitize=address` is not supported together with `-fsanitize=thread`
			MESENFLAGS += -fsanitize=thread
		else
$(warning Unrecognised $$(SANITIZER) value: $(SANITIZER))
		endif
		# `-Wl,-z,defs` is incompatible with the sanitizers in a shared lib, unless the sanitizer libs are linked dynamically; hence `-shared-libsan` (not the default for Clang).
		# It seems impossible to link dynamically against two sanitizers at the same time, but that might be a Clang limitation.
		ifneq ($(USE_GCC),true)
			MESENFLAGS += -shared-libsan
		endif
	endif
endif

ifeq ($(PGO),profile)
	MESENFLAGS += ${PROFILE_GEN_FLAG}
endif

ifeq ($(PGO),optimize)
	MESENFLAGS += ${PROFILE_USE_FLAG}
endif

ifneq ($(STATICLINK),false)
	LINKOPTIONS += -static-libgcc -static-libstdc++
endif

ifeq ($(MESENOS),osx)
	LINKOPTIONS += -framework Foundation -framework Cocoa
endif

CXXFLAGS = -fPIC -Wall --std=c++17 $(MESENFLAGS) $(SDL2INC) -I $(realpath ./) -I $(realpath ./Core) -I $(realpath ./Utilities) -I $(realpath ./Sdl) -I $(realpath ./Linux) -I $(realpath ./MacOS)
OBJCXXFLAGS = $(CXXFLAGS) -framework Foundation -framework Cocoa
CFLAGS = -fPIC -Wall $(MESENFLAGS)

OBJFOLDER := obj.$(MESENPLATFORM)
DEBUGFOLDER := bin/$(MESENPLATFORM)/Debug
RELEASEFOLDER := bin/$(MESENPLATFORM)/Release
ifeq ($(DEBUG), 0)
	OUTFOLDER = $(RELEASEFOLDER)
	BUILD_TYPE := Release
	OPTIMIZEUI := -p:OptimizeUi=true
else
	OUTFOLDER = $(DEBUGFOLDER)
	BUILD_TYPE := Debug
	OPTIMIZEUI :=
endif


ifeq ($(USE_AOT),true)
	PUBLISHFLAGS ?=  -r $(MESENPLATFORM) -p:PublishSingleFile=false -p:PublishAot=true -p:SelfContained=true
else
	PUBLISHFLAGS ?=  -r $(MESENPLATFORM) --no-self-contained true -p:PublishSingleFile=true
endif


CORESRC := $(shell find Core -name '*.cpp')
COREOBJ := $(CORESRC:.cpp=.o)

UTILSRC := $(shell find Utilities -name '*.cpp' -o -name '*.c')
UTILOBJ := $(addsuffix .o,$(basename $(UTILSRC)))

SDLSRC := $(shell find Sdl -name '*.cpp')
SDLOBJ := $(SDLSRC:.cpp=.o)

SEVENZIPSRC := $(shell find SevenZip -name '*.c')
SEVENZIPOBJ := $(SEVENZIPSRC:.c=.o)

LUASRC := $(shell find Lua -name '*.c')
LUAOBJ := $(LUASRC:.c=.o)

ifeq ($(MESENOS),linux)
	LINUXSRC := $(shell find Linux -name '*.cpp')
else
	LINUXSRC :=
endif
LINUXOBJ := $(LINUXSRC:.cpp=.o)

ifeq ($(MESENOS),osx)
	MACOSSRC := $(shell find MacOS -name '*.mm')
else
	MACOSSRC :=
endif
MACOSOBJ := $(MACOSSRC:.mm=.o)

DLLSRC := $(shell find InteropDLL -name '*.cpp')
DLLOBJ := $(DLLSRC:.cpp=.o)

ifeq ($(SYSTEM_LIBEVDEV), true)
	LIBEVDEVLIB := $(shell pkg-config --libs libevdev)
	LIBEVDEVINC := $(shell pkg-config --cflags libevdev)
else
	LIBEVDEVSRC := $(shell find Linux/libevdev -name '*.c')
	LIBEVDEVOBJ := $(LIBEVDEVSRC:.c=.o)
	LIBEVDEVINC := -I../
endif

ifeq ($(MESENOS),linux)
	X11LIB := -lX11
else
	X11LIB :=
endif

STDCXXLIB := -lstdc++

ifeq ($(MESENOS),osx)
	LIBEVDEVOBJ :=
	LIBEVDEVINC :=
	LIBEVDEVSRC :=
	STDCXXLIB :=
	PUBLISHFLAGS := -t:BundleApp -p:UseAppHost=true -p:RuntimeIdentifier=$(MESENPLATFORM) -p:SelfContained=true -p:PublishSingleFile=false -p:PublishReadyToRun=false
endif

all: ui

STATIC_CORE := false

ifneq ($(STATIC_CORE),false)
ui: InteropDLL/$(OBJFOLDER)/$(STATICLIB) InteropDLL/staticlink.targets
PUBLISHFLAGS += -p:StaticCore=true
else
ui: InteropDLL/$(OBJFOLDER)/$(SHAREDLIB)
endif
# Why do we `dotnet publish` twice?
# Well, Mesen2 wants to be entirely self-contained, *but* it depends on two native libraries
# (`libSkiaSharp` and `libHarfBuzzSharp`). It wants to embark those libraries in its `Dependencies.zip`
# which gets unpacked on startup.
# So, Mesen2 needs `Dependencies.zip` to contain both libraries before being build itself.
# BUT, msbuild only copies the libraries to `$(OUTFOLDER)` *after* building Mesen2!
# So, we need to build once to get the libs (but the flags there don't matter, it's a dummy build after all)
# and *then* build for real.
ui:
	mkdir -p $(OUTFOLDER)/Dependencies
	rm -fr $(OUTFOLDER)/Dependencies/*
	-cp InteropDLL/$(OBJFOLDER)/$(SHAREDLIB) $(OUTFOLDER)/$(SHAREDLIB)
	cd UI && dotnet publish -c $(BUILD_TYPE) $(OPTIMIZEUI) -r $(MESENPLATFORM)
	cd UI && dotnet publish -c $(BUILD_TYPE) $(OPTIMIZEUI) $(PUBLISHFLAGS)
	rm -f InteropDLL/staticlink.targets

core: InteropDLL/$(OBJFOLDER)/$(SHAREDLIB)

pgohelper: InteropDLL/$(OBJFOLDER)/$(SHAREDLIB)
	mkdir -p PGOHelper/$(OBJFOLDER) && cd PGOHelper/$(OBJFOLDER) && $(CXX) $(CXXFLAGS) $(LINKCHECKUNRESOLVED) -o pgohelper ../PGOHelper.cpp ../../bin/pgohelperlib.so -pthread $(STDCXXLIB) $(SDL2LIB) $(LIBEVDEVLIB) $(X11LIB)

%.o: %.c
	$(CC) $(CFLAGS) -c $< -o $@

%.o: %.cpp
	$(CXX) $(CXXFLAGS) -c $< -o $@

%.o: %.mm
	$(CXX) $(OBJCXXFLAGS) -c $< -o $@

InteropDLL/$(OBJFOLDER)/$(SHAREDLIB): $(SEVENZIPOBJ) $(LUAOBJ) $(UTILOBJ) $(COREOBJ) $(SDLOBJ) $(LIBEVDEVOBJ) $(LINUXOBJ) $(DLLOBJ) $(MACOSOBJ)
	mkdir -p bin
	mkdir -p InteropDLL/$(OBJFOLDER)
	$(CXX) $(CXXFLAGS) $(LINKOPTIONS) $(LINKCHECKUNRESOLVED) -shared -o $(SHAREDLIB) $^ $(SDL2INC) -pthread $(STDCXXLIB) $(SDL2LIB) $(LIBEVDEVLIB) $(X11LIB)
	cp $(SHAREDLIB) bin/pgohelperlib.so
	mv $(SHAREDLIB) InteropDLL/$(OBJFOLDER)/

InteropDLL/$(OBJFOLDER)/$(STATICLIB): $(SEVENZIPOBJ) $(LUAOBJ) $(UTILOBJ) $(COREOBJ) $(SDLOBJ) $(LIBEVDEVOBJ) $(LINUXOBJ) $(DLLOBJ) $(MACOSOBJ)
	mkdir -p bin
	mkdir -p InteropDLL/$(OBJFOLDER)
	$(AR) rcusT $@ $^

InteropDLL/staticlink.targets:
	echo '<Project>' >$@
	echo '<ItemGroup>' >>$@
	echo '<DirectPInvoke Include="MesenCore" />' >> $@
	echo '<NativeLibrary Include="../InteropDLL/$(OBJFOLDER)/$(STATICLIB) $(CXXFLAGS) $(LINKOPTIONS) $(LINKCHECKUNRESOLVED) $(SDL2INC) -pthread $(STDCXXLIB) $(SDL2LIB) $(LIBEVDEVLIB) $(X11LIB)" />' >>$@
	echo '</ItemGroup>' >>$@
	echo '</Project>' >>$@


pgo:
	./buildPGO.sh

run:
	$(OUTFOLDER)/$(MESENPLATFORM)/publish/Mesen

clean:
	rm -rf bin
	rm -rf $(COREOBJ)
	rm -rf $(UTILOBJ)
	rm -rf $(LINUXOBJ) $(LIBEVDEVOBJ)
	rm -rf $(SDLOBJ)
	rm -rf $(SEVENZIPOBJ)
	rm -rf $(LUAOBJ)
	rm -rf $(MACOSOBJ)
	rm -rf $(DLLOBJ)
