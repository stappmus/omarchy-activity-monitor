CXX ?= c++
CPPFLAGS ?=
CXXFLAGS ?= -O2 -pipe
LDFLAGS ?=
LDLIBS ?= -ldl

# -fcf-protection is only supported on x86 targets; probe the compiler so
# ARM/AArch64 (e.g. Apple Silicon / Asahi) builds don't fail.
CF_PROTECTION := $(shell printf 'int main(){return 0;}\n' | $(CXX) -fcf-protection -x c++ - -o /dev/null >/dev/null 2>&1 && echo -fcf-protection)

SAMPLER_FLAGS = -std=c++17 -DNDEBUG -fno-exceptions -fno-rtti \
	-fstack-protector-strong $(CF_PROTECTION) -D_FORTIFY_SOURCE=3 \
	-Wall -Wextra -Wpedantic -Werror -ffile-prefix-map=$(CURDIR)=.
SAMPLER_LDFLAGS = -Wl,--as-needed -Wl,-z,relro -Wl,-z,now \
	-Wl,--build-id=none -s

.PHONY: all clean

all: activity-sampler

activity-sampler: activity-sampler.cpp
	LC_ALL=C $(CXX) $(CPPFLAGS) $(CXXFLAGS) $(SAMPLER_FLAGS) \
		$(LDFLAGS) $(SAMPLER_LDFLAGS) -o $@ $< $(LDLIBS)

clean:
	rm -f -- activity-sampler
