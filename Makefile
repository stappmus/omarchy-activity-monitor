CXX ?= c++
CPPFLAGS ?=
CXXFLAGS ?= -O2 -pipe
LDFLAGS ?=
LDLIBS ?= -ldl

# -fcf-protection is Intel CET and is rejected on aarch64 (and similar).
UNAME_M := $(shell uname -m)
ifneq (,$(filter x86_64 amd64 i686,$(UNAME_M)))
CF_PROTECTION := -fcf-protection
endif

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
