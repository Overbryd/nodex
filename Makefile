MIX := mix
EXAMPLE_CFLAGS := -g -O2 -std=c99 -pedantic -Wcomment -Wall
# we need to compile position independent code
EXAMPLE_CFLAGS += -fpic -DPIC
# For some reason __erl_errno is undefined unless _REENTRANT is defined
EXAMPLE_CFLAGS += -D_REENTRANT
# turn warnings into errors
# EXAMPLE_CFLAGS += -Werror
# ignore unused variables
# EXAMPLE_CFLAGS += -Wno-unused-variable
# ignore unused parameter warnings
EXAMPLE_CFLAGS += -Wno-unused-parameter

# set erlang include path
ERLANG_PATH := $(shell erl -eval 'io:format("~s", [lists:concat([code:root_dir(), "/erts-", erlang:system_info(version)])])' -s init stop -noshell)
ERL_INTERFACE := $(wildcard $(ERLANG_PATH)/../lib/erl_interface-*)

EXAMPLE_CFLAGS += -I$(ERLANG_PATH)/include
EXAMPLE_CFLAGS += -L$(ERL_INTERFACE)/lib
EXAMPLE_CFLAGS += -I$(ERL_INTERFACE)/include
EXAMPLE_CFLAGS += -lerl_interface -lei

# platform specific includes
UNAME := $(shell uname -s | tr '[:upper:]' '[:lower:]')
ifneq ($(wilcard Makefile.$(UNAME)),)
	include Makefile.$(UNAME)
endif

.PHONY: all

all: example

example: priv/example_client priv/just_exit
	$(MIX) compile

priv/%: c_src/%.c
	$(CC) $(EXAMPLE_CFLAGS) $(EXAMPLE_LDFLAGS) -o $@ $<

clean:
	$(RM) -r priv/*
	$(RM) cnodex-*.tar

publish: clean
	$(MIX) hex.publish

