#
# Makefile for ZeroTier SDK on Linux
#
# Targets
#   all: build every target possible on host system, plus tests
#   check: reports OK/FAIL of built targets
#   tests: build only test applications for host system
#   clean: removes all built files, objects, other trash

GENERATED_FILES :=
DOC_DIR = doc

# Automagically pick clang or gcc, with preference for clang
# This is only done if we have not overridden these with an environment or CLI variable
ifeq ($(origin CC),default)
	CC=$(shell if [ -e /usr/bin/clang ]; then echo clang; else echo gcc; fi)
endif
ifeq ($(origin CXX),default)
	CXX=$(shell if [ -e /usr/bin/clang++ ]; then echo clang++; else echo g++; fi)
endif

#UNAME_M=$(shell $(CC) -dumpmachine | cut -d '-' -f 1)

INCLUDES?=
DEFS?=
LDLIBS?=

include objects.mk

ifeq ($(ZT_DEBUG),1)
	DEFS+=-DZT_TRACE
	CFLAGS+=-Wall -g -pthread $(INCLUDES) $(DEFS)
	CXXFLAGS+=-Wall -g -pthread $(INCLUDES) $(DEFS)
	LDFLAGS=-ldl
	STRIP?=echo
	# The following line enables optimization for the crypto code, since
	# C25519 in particular is almost UNUSABLE in -O0 even on a 3ghz box!
ext/lz4/lz4.o node/Salsa20.o node/SHA512.o node/C25519.o node/Poly1305.o: CFLAGS = -Wall -O2 -g -pthread $(INCLUDES) $(DEFS)
else
	CFLAGS?=-O3 -fstack-protector
	CFLAGS+=-Wall -fPIE -fvisibility=hidden -pthread $(INCLUDES) -DNDEBUG $(DEFS)
	CXXFLAGS?=-O3 -fstack-protector
	CXXFLAGS+=-Wall -Wreorder -fPIE -fvisibility=hidden -fno-rtti -pthread $(INCLUDES) -DNDEBUG $(DEFS)
	LDFLAGS=-ldl -pie -Wl,-z,relro,-z,now
	STRIP?=strip
	STRIP+=--strip-all
endif

# Debug output for ZeroTier service
ifeq ($(ZT_TRACE),1)
	DEFS+=-DZT_TRACE
endif

# Debug output for lwIP
ifeq ($(SDK_LWIP_DEBUG),1)
	LWIP_FLAGS:=SDK_LWIP_DEBUG=1
endif

# Debug output for the SDK
# Specific levels can be controlled in src/SDK_Debug.h
ifeq ($(SDK_DEBUG),1)
	DEFS+=-DSDK_DEBUG -g
endif
# Log debug chatter to file, path is determined by environment variable ZT_SDK_LOGFILE
ifeq ($(SDK_DEBUG_LOG_TO_FILE),1)
	DEFS+=-DSDK_DEBUG_LOG_TO_FILE
endif

all: shared_lib check

remove_only_intermediates:
	-find . -type f \( -name '*.o' -o -name '*.so' \) -delete

linux_shared_lib: remove_only_intermediates $(OBJS)
	mkdir -p build/linux_shared_lib
	$(CXX) $(CXXFLAGS) $(LDFLAGS) $(DEFS) -DZT_SDK -DZT_ONE_NO_ROOT_CHECK -Iext/lwip/src/include -Iext/lwip/src/include/ipv4 -Iext/lwip/src/include/ipv6 -Izerotierone/osdep -Izerotierone/node -Isrc -o build/zerotier-sdk-service $(OBJS) zerotierone/service/OneService.cpp src/SDK_EthernetTap.cpp src/SDK_Proxy.cpp zerotierone/one.cpp -x c src/SDK_RPC.c $(LDLIBS) -ldl
	# Build liblwip.so which must be placed in ZT home for zerotier-netcon-service to work
	make -f make-liblwip.mk $(LWIP_FLAGS)
	# Use gcc not clang to build standalone intercept library since gcc is typically used for libc and we want to ensure maximal ABI compatibility
	cd src ; gcc $(DEFS) -O2 -Wall -std=c99 -fPIC -DVERBOSE -D_GNU_SOURCE -DSDK_INTERCEPT -I. -I../zerotierone/node -nostdlib -shared -o libztintercept.so SDK_Sockets.c SDK_Intercept.c SDK_Debug.c SDK_RPC.c -ldl
	cp src/libztintercept.so build/linux_shared_lib/libztintercept.so
	ln -sf zerotier-sdk-service zerotier-cli
	ln -sf zerotier-sdk-service zerotier-idtool

# Check for the presence of built frameworks/bundles/libaries
check:
	./check.sh build/lwip/liblwip.so
	./check.sh build/linux_shared_lib/libztintercept.so

	./check.sh build/
	./check.sh build/android_jni_lib/arm64-v8a/libZeroTierJNI.so
	./check.sh build/android_jni_lib/armeabi/libZeroTierJNI.so
	./check.sh build/android_jni_lib/armeabi-v7a/libZeroTierJNI.so
	./check.sh build/android_jni_lib/mips/libZeroTierJNI.so
	./check.sh build/android_jni_lib/mips64/libZeroTierJNI.so
	./check.sh build/android_jni_lib/x86/libZeroTierJNI.so
	./check.sh build/android_jni_lib/x86_64/libZeroTierJNI.so

# Tests
TEST_OBJDIR := build/tests
TEST_SOURCES := $(wildcard tests/*.c)
TEST_TARGETS := $(addprefix build/tests/$(OSTYPE).,$(notdir $(TEST_SOURCES:.c=.out)))

build/tests/$(OSTYPE).%.out: tests/%.c
	-$(CC) $(CC_FLAGS) -o $@ $<

$(TEST_OBJDIR):
	mkdir -p $(TEST_OBJDIR)

tests: $(TEST_OBJDIR) $(TEST_TARGETS)
	mkdir -p build/tests; 

clean:
	rm -rf zerotier-cli zerotier-idtool
	rm -rf build/*
	find . -type f \( -name '*.o' -o -name '*.so' -o -name '*.o.d' -o -name '*.out' -o -name '*.log' \) -delete
	# Remove junk generated by Android builds
	cd integrations/Android/proj; ./gradlew clean
	rm -rf integrations/Android/proj/.gradle
	rm -rf integrations/Android/proj/.idea
	rm -rf integrations/Android/proj/build
