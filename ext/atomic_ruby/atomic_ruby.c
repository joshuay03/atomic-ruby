#include "atomic_ruby.h"

typedef struct {
  volatile VALUE value;
#ifdef ATOMIC_RUBY_RACTOR_SAFE
  VALUE initialized_ractor;
#endif
} atomic_ruby_atom_t;

static void atomic_ruby_atom_mark(void *ptr) {
  atomic_ruby_atom_t *atomic_ruby_atom = (atomic_ruby_atom_t *)ptr;
  rb_gc_mark_movable(atomic_ruby_atom->value);
#ifdef ATOMIC_RUBY_RACTOR_SAFE
  rb_gc_mark_movable(atomic_ruby_atom->initialized_ractor);
#endif
}

static void atomic_ruby_atom_free(void *ptr) {
  atomic_ruby_atom_t *atomic_ruby_atom = (atomic_ruby_atom_t *)ptr;
  xfree(atomic_ruby_atom);
}

static size_t atomic_ruby_atom_memsize(const void *ptr) {
  return sizeof(atomic_ruby_atom_t);
}

static void atomic_ruby_atom_compact(void *ptr) {
  atomic_ruby_atom_t *atomic_ruby_atom = (atomic_ruby_atom_t *)ptr;
  atomic_ruby_atom->value = rb_gc_location(atomic_ruby_atom->value);
#ifdef ATOMIC_RUBY_RACTOR_SAFE
  atomic_ruby_atom->initialized_ractor = rb_gc_location(atomic_ruby_atom->initialized_ractor);
#endif
}

static const rb_data_type_t atomic_ruby_atom_type = {
  .wrap_struct_name = "AtomicRuby::Atom",
  .function = {
    .dmark = atomic_ruby_atom_mark,
    .dfree = atomic_ruby_atom_free,
    .dsize = atomic_ruby_atom_memsize,
    .dcompact = atomic_ruby_atom_compact
  },
#ifdef ATOMIC_RUBY_RACTOR_SAFE
  .flags = RUBY_TYPED_FREE_IMMEDIATELY | RUBY_TYPED_WB_PROTECTED | RUBY_TYPED_FROZEN_SHAREABLE
#else
  .flags = RUBY_TYPED_FREE_IMMEDIATELY | RUBY_TYPED_WB_PROTECTED
#endif
};

#ifdef ATOMIC_RUBY_RACTOR_SAFE
static void ensure_value_shareable(VALUE self, atomic_ruby_atom_t *atom, VALUE value) {
  bool check_shareable = NIL_P(atom->initialized_ractor);

  if (!check_shareable) {
    VALUE current_ractor = rb_funcall(rb_cRactor, rb_intern("current"), 0);
    if (current_ractor != atom->initialized_ractor) {
      check_shareable = true;
      RB_OBJ_WRITE(self, &atom->initialized_ractor, Qnil);
    }
  }

  if (check_shareable && !rb_ractor_shareable_p(value)) {
    rb_raise(rb_eArgError, "value must be a shareable object when used across ractors");
  }
}
#endif

static VALUE rb_cAtom_allocate(VALUE klass) {
  atomic_ruby_atom_t *atomic_ruby_atom;
  VALUE obj = TypedData_Make_Struct(klass, atomic_ruby_atom_t, &atomic_ruby_atom_type, atomic_ruby_atom);
  RB_OBJ_WRITE(obj, &atomic_ruby_atom->value, Qnil);
#ifdef ATOMIC_RUBY_RACTOR_SAFE
  VALUE current_ractor = rb_funcall(rb_cRactor, rb_intern("current"), 0);
  RB_OBJ_WRITE(obj, &atomic_ruby_atom->initialized_ractor, current_ractor);
#endif
  return obj;
}

static VALUE rb_cAtom_initialize(VALUE self, VALUE value) {
  atomic_ruby_atom_t *atomic_ruby_atom;
  TypedData_Get_Struct(self, atomic_ruby_atom_t, &atomic_ruby_atom_type, atomic_ruby_atom);
  RB_OBJ_WRITE(self, &atomic_ruby_atom->value, value);
#ifdef ATOMIC_RUBY_RACTOR_SAFE
  rb_obj_freeze(self);
  FL_SET_RAW(self, RUBY_FL_SHAREABLE);
#endif
  return self;
}

static VALUE rb_cAtom_value(VALUE self) {
  atomic_ruby_atom_t *atomic_ruby_atom;
  TypedData_Get_Struct(self, atomic_ruby_atom_t, &atomic_ruby_atom_type, atomic_ruby_atom);
  VALUE value = (VALUE)RUBY_ATOMIC_PTR_LOAD(atomic_ruby_atom->value);
#ifdef ATOMIC_RUBY_RACTOR_SAFE
  ensure_value_shareable(self, atomic_ruby_atom, value);
#endif
  return value;
}

static VALUE rb_cAtom_swap(VALUE self) {
  atomic_ruby_atom_t *atomic_ruby_atom;
  TypedData_Get_Struct(self, atomic_ruby_atom_t, &atomic_ruby_atom_type, atomic_ruby_atom);

  VALUE expected_old_value, new_value;
  do {
    expected_old_value = atomic_ruby_atom->value;
    new_value = rb_yield(expected_old_value);
#ifdef ATOMIC_RUBY_RACTOR_SAFE
    ensure_value_shareable(self, atomic_ruby_atom, new_value);
#endif
  } while (RUBY_ATOMIC_VALUE_CAS(atomic_ruby_atom->value, expected_old_value, new_value) != expected_old_value);
  RB_OBJ_WRITTEN(self, expected_old_value, new_value);

  return new_value;
}

#ifdef ATOMIC_RUBY_RACTOR_SAFE
static VALUE rb_cAtom_initialized_ractor(VALUE self) {
  atomic_ruby_atom_t *atomic_ruby_atom;
  TypedData_Get_Struct(self, atomic_ruby_atom_t, &atomic_ruby_atom_type, atomic_ruby_atom);
  return atomic_ruby_atom->initialized_ractor;
}
#endif

RUBY_FUNC_EXPORTED void Init_atomic_ruby(void) {
#ifdef ATOMIC_RUBY_RACTOR_SAFE
  rb_ext_ractor_safe(true);
#endif

  VALUE rb_mAtomicRuby = rb_define_module("AtomicRuby");
  VALUE rb_cAtom = rb_define_class_under(rb_mAtomicRuby, "Atom", rb_cObject);

  rb_define_alloc_func(rb_cAtom, rb_cAtom_allocate);
  rb_define_private_method(rb_cAtom, "_initialize", rb_cAtom_initialize, 1);
  rb_define_private_method(rb_cAtom, "_value", rb_cAtom_value, 0);
  rb_define_private_method(rb_cAtom, "_swap", rb_cAtom_swap, 0);

#ifdef ATOMIC_RUBY_RACTOR_SAFE
  rb_define_private_method(rb_cAtom, "_initialized_ractor", rb_cAtom_initialized_ractor, 0);
  rb_define_const(rb_mAtomicRuby, "RACTOR_SAFE", Qtrue);
#else
  rb_define_const(rb_mAtomicRuby, "RACTOR_SAFE", Qfalse);
#endif
}
