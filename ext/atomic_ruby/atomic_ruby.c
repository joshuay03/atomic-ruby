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

typedef struct {
  volatile VALUE value;
  volatile VALUE next;
} atomic_ruby_queue_node_t;

static void atomic_ruby_queue_node_mark(void *ptr) {
  atomic_ruby_queue_node_t *atomic_ruby_queue_node = (atomic_ruby_queue_node_t *)ptr;
  rb_gc_mark_movable(atomic_ruby_queue_node->value);
  rb_gc_mark_movable(atomic_ruby_queue_node->next);
}

static void atomic_ruby_queue_node_free(void *ptr) {
  xfree(ptr);
}

static size_t atomic_ruby_queue_node_memsize(const void *ptr) {
  return sizeof(atomic_ruby_queue_node_t);
}

static void atomic_ruby_queue_node_compact(void *ptr) {
  atomic_ruby_queue_node_t *atomic_ruby_queue_node = (atomic_ruby_queue_node_t *)ptr;
  atomic_ruby_queue_node->value = rb_gc_location(atomic_ruby_queue_node->value);
  atomic_ruby_queue_node->next = rb_gc_location(atomic_ruby_queue_node->next);
}

static const rb_data_type_t atomic_ruby_queue_node_type = {
  .wrap_struct_name = "AtomicRuby::AtomicQueue::Node",
  .function = {
    .dmark = atomic_ruby_queue_node_mark,
    .dfree = atomic_ruby_queue_node_free,
    .dsize = atomic_ruby_queue_node_memsize,
    .dcompact = atomic_ruby_queue_node_compact
  },
  .flags = RUBY_TYPED_FREE_IMMEDIATELY | RUBY_TYPED_WB_PROTECTED
};

static VALUE rb_cAtomicQueueNode;

static VALUE atomic_ruby_queue_node_new(VALUE value, VALUE next) {
  atomic_ruby_queue_node_t *atomic_ruby_queue_node;
  VALUE obj = TypedData_Make_Struct(rb_cAtomicQueueNode, atomic_ruby_queue_node_t, &atomic_ruby_queue_node_type, atomic_ruby_queue_node);
  RB_OBJ_WRITE(obj, &atomic_ruby_queue_node->value, value);
  RB_OBJ_WRITE(obj, &atomic_ruby_queue_node->next, next);
  return obj;
}

typedef struct {
  volatile VALUE head;
  volatile VALUE tail;
  volatile rb_atomic_t count;
} atomic_ruby_queue_t;

static void atomic_ruby_queue_mark(void *ptr) {
  atomic_ruby_queue_t *atomic_ruby_queue = (atomic_ruby_queue_t *)ptr;
  rb_gc_mark_movable(atomic_ruby_queue->head);
  rb_gc_mark_movable(atomic_ruby_queue->tail);
}

static void atomic_ruby_queue_free(void *ptr) {
  xfree(ptr);
}

static size_t atomic_ruby_queue_memsize(const void *ptr) {
  return sizeof(atomic_ruby_queue_t);
}

static void atomic_ruby_queue_compact(void *ptr) {
  atomic_ruby_queue_t *atomic_ruby_queue = (atomic_ruby_queue_t *)ptr;
  atomic_ruby_queue->head = rb_gc_location(atomic_ruby_queue->head);
  atomic_ruby_queue->tail = rb_gc_location(atomic_ruby_queue->tail);
}

static const rb_data_type_t atomic_ruby_queue_type = {
  .wrap_struct_name = "AtomicRuby::AtomicQueue",
  .function = {
    .dmark = atomic_ruby_queue_mark,
    .dfree = atomic_ruby_queue_free,
    .dsize = atomic_ruby_queue_memsize,
    .dcompact = atomic_ruby_queue_compact
  },
  .flags = RUBY_TYPED_FREE_IMMEDIATELY | RUBY_TYPED_WB_PROTECTED
};

static VALUE rb_cAtomicQueue_allocate(VALUE klass) {
  atomic_ruby_queue_t *atomic_ruby_queue;
  VALUE obj = TypedData_Make_Struct(klass, atomic_ruby_queue_t, &atomic_ruby_queue_type, atomic_ruby_queue);
  RB_OBJ_WRITE(obj, &atomic_ruby_queue->head, Qnil);
  RB_OBJ_WRITE(obj, &atomic_ruby_queue->tail, Qnil);
  atomic_ruby_queue->count = 0;
  return obj;
}

static VALUE rb_cAtomicQueue_initialize(VALUE self) {
  atomic_ruby_queue_t *atomic_ruby_queue;
  TypedData_Get_Struct(self, atomic_ruby_queue_t, &atomic_ruby_queue_type, atomic_ruby_queue);

  VALUE sentinel = atomic_ruby_queue_node_new(Qnil, Qnil);
  RB_OBJ_WRITE(self, &atomic_ruby_queue->head, sentinel);
  RB_OBJ_WRITE(self, &atomic_ruby_queue->tail, sentinel);

  return self;
}

static VALUE rb_cAtomicQueue_push(VALUE self, VALUE value) {
  atomic_ruby_queue_t *atomic_ruby_queue;
  TypedData_Get_Struct(self, atomic_ruby_queue_t, &atomic_ruby_queue_type, atomic_ruby_queue);

  VALUE new_node = atomic_ruby_queue_node_new(value, Qnil);

  VALUE tail;
  while (1) {
    tail = (VALUE)RUBY_ATOMIC_PTR_LOAD(atomic_ruby_queue->tail);
    atomic_ruby_queue_node_t *tail_node;
    TypedData_Get_Struct(tail, atomic_ruby_queue_node_t, &atomic_ruby_queue_node_type, tail_node);
    VALUE tail_next = (VALUE)RUBY_ATOMIC_PTR_LOAD(tail_node->next);

    if (tail != (VALUE)RUBY_ATOMIC_PTR_LOAD(atomic_ruby_queue->tail)) continue;

    if (tail_next != Qnil) {
      RUBY_ATOMIC_VALUE_CAS(atomic_ruby_queue->tail, tail, tail_next);
      RB_OBJ_WRITTEN(self, tail, tail_next);
      continue;
    }

    if (RUBY_ATOMIC_VALUE_CAS(tail_node->next, Qnil, new_node) == Qnil) {
      RB_OBJ_WRITTEN(tail, Qnil, new_node);
      break;
    }
  }

  RUBY_ATOMIC_VALUE_CAS(atomic_ruby_queue->tail, tail, new_node);
  RB_OBJ_WRITTEN(self, tail, new_node);
  RUBY_ATOMIC_INC(atomic_ruby_queue->count);

  return self;
}

static VALUE rb_cAtomicQueue_pop(VALUE self) {
  atomic_ruby_queue_t *atomic_ruby_queue;
  TypedData_Get_Struct(self, atomic_ruby_queue_t, &atomic_ruby_queue_type, atomic_ruby_queue);

  VALUE head, head_next, result;
  while (1) {
    head = (VALUE)RUBY_ATOMIC_PTR_LOAD(atomic_ruby_queue->head);
    VALUE tail = (VALUE)RUBY_ATOMIC_PTR_LOAD(atomic_ruby_queue->tail);
    atomic_ruby_queue_node_t *head_node;
    TypedData_Get_Struct(head, atomic_ruby_queue_node_t, &atomic_ruby_queue_node_type, head_node);
    head_next = (VALUE)RUBY_ATOMIC_PTR_LOAD(head_node->next);

    if (head != (VALUE)RUBY_ATOMIC_PTR_LOAD(atomic_ruby_queue->head)) continue;

    if (head == tail) {
      if (head_next == Qnil) return Qnil;

      RUBY_ATOMIC_VALUE_CAS(atomic_ruby_queue->tail, tail, head_next);
      RB_OBJ_WRITTEN(self, tail, head_next);
      continue;
    }

    atomic_ruby_queue_node_t *next_node;
    TypedData_Get_Struct(head_next, atomic_ruby_queue_node_t, &atomic_ruby_queue_node_type, next_node);
    result = next_node->value;

    if (RUBY_ATOMIC_VALUE_CAS(atomic_ruby_queue->head, head, head_next) == head) {
      RB_OBJ_WRITTEN(self, head, head_next);
      break;
    }
  }

  RUBY_ATOMIC_DEC(atomic_ruby_queue->count);
  return result;
}

static VALUE rb_cAtomicQueue_size(VALUE self) {
  atomic_ruby_queue_t *atomic_ruby_queue;
  TypedData_Get_Struct(self, atomic_ruby_queue_t, &atomic_ruby_queue_type, atomic_ruby_queue);
  return UINT2NUM((unsigned int)RUBY_ATOMIC_LOAD(atomic_ruby_queue->count));
}

static VALUE rb_cAtomicQueue_empty_p(VALUE self) {
  atomic_ruby_queue_t *atomic_ruby_queue;
  TypedData_Get_Struct(self, atomic_ruby_queue_t, &atomic_ruby_queue_type, atomic_ruby_queue);
  return RUBY_ATOMIC_LOAD(atomic_ruby_queue->count) == 0 ? Qtrue : Qfalse;
}

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

  VALUE rb_cAtomicQueue = rb_define_class_under(rb_mAtomicRuby, "AtomicQueue", rb_cObject);
  rb_cAtomicQueueNode = rb_define_class_under(rb_cAtomicQueue, "Node", rb_cObject);
  rb_undef_alloc_func(rb_cAtomicQueueNode);

  rb_define_alloc_func(rb_cAtomicQueue, rb_cAtomicQueue_allocate);
  rb_define_private_method(rb_cAtomicQueue, "_initialize", rb_cAtomicQueue_initialize, 0);
  rb_define_private_method(rb_cAtomicQueue, "_push", rb_cAtomicQueue_push, 1);
  rb_define_private_method(rb_cAtomicQueue, "_pop", rb_cAtomicQueue_pop, 0);
  rb_define_private_method(rb_cAtomicQueue, "_size", rb_cAtomicQueue_size, 0);
  rb_define_private_method(rb_cAtomicQueue, "_empty_p", rb_cAtomicQueue_empty_p, 0);
}
