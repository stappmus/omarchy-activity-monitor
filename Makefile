CXX ?= c++
CPPFLAGS ?=
CXXFLAGS ?= -O2 -pipe
LDFLAGS ?=
LDLIBS ?= -ldl

# Control-flow hardening is target-specific: -fcf-protection on x86 and
# -mbranch-protection on ARM/AArch64 (e.g. Apple Silicon / Asahi). Probe the
# compiler so each target gets the flag it supports and none fails to build.
cxx_accepts = $(shell printf 'int main(){return 0;}\n' | $(CXX) $(1) -x c++ - -o /dev/null >/dev/null 2>&1 && echo $(1))
CF_PROTECTION := $(call cxx_accepts,-fcf-protection) \
	$(call cxx_accepts,-mbranch-protection=standard)

SAMPLER_ARCH := $(shell $(CXX) -dumpmachine | cut -d- -f1)

SAMPLER_FLAGS = -std=c++17 -DNDEBUG -fno-exceptions -fno-rtti \
	-fstack-protector-strong $(CF_PROTECTION) -D_FORTIFY_SOURCE=3 \
	-Wall -Wextra -Wpedantic -Werror -ffile-prefix-map=$(CURDIR)=.
SAMPLER_LDFLAGS = -Wl,--as-needed -Wl,-z,relro -Wl,-z,now \
	-Wl,--build-id=none -s

.PHONY: all prebuilt clean

all: activity-sampler

activity-sampler: activity-sampler.cpp
	LC_ALL=C $(CXX) $(CPPFLAGS) $(CXXFLAGS) $(SAMPLER_FLAGS) \
		$(LDFLAGS) $(SAMPLER_LDFLAGS) -o $@ $< $(LDLIBS)

# Rebuild the committed binary for the compiler's target, e.g.
# make prebuilt CXX=aarch64-linux-gnu-g++
prebuilt:
	$(MAKE) -B activity-sampler
	cp -- activity-sampler activity-sampler-$(SAMPLER_ARCH)

clean:
	rm -f -- activity-sampler
