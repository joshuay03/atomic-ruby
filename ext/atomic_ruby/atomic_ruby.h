#ifndef ATOMIC_RUBY_ATOM_H
#define ATOMIC_RUBY_ATOM_H 1

#include "ruby.h"
#include "ruby/atomic.h"
#include "ruby/version.h"

#if RUBY_API_VERSION_CODE >= 40000
#define ATOMIC_RUBY_RACTOR_SAFE 1
#include "ruby/ractor.h"
#endif

#endif /* ATOMIC_RUBY_ATOM_H */
