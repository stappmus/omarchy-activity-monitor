CXX ?= c++
CPPFLAGS ?=
CXXFLAGS ?= -O2 -pipe
LDFLAGS ?=
LDLIBS ?= -ldl

# -fcf-protection is x86-only (not supported on aarch64, e.g. Apple Silicon).
CF_PROTECTION := $(shell $(CXX) -dumpmachine | grep -qE '^(x86_64|i[3-6]86)' && echo -fcf-protection)

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
