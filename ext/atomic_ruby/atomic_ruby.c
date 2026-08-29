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

typedef struct {
  volatile VALUE prev;
  volatile VALUE next;
  volatile VALUE thread;
} atomic_ruby_condition_variable_waiter_t;

static void atomic_ruby_condition_variable_waiter_mark(void *ptr) {
  atomic_ruby_condition_variable_waiter_t *atomic_ruby_condition_variable_waiter = (atomic_ruby_condition_variable_waiter_t *)ptr;
  rb_gc_mark_movable(atomic_ruby_condition_variable_waiter->prev);
  rb_gc_mark_movable(atomic_ruby_condition_variable_waiter->next);
  rb_gc_mark_movable(atomic_ruby_condition_variable_waiter->thread);
}

static void atomic_ruby_condition_variable_waiter_free(void *ptr) {
  xfree(ptr);
}

static size_t atomic_ruby_condition_variable_waiter_memsize(const void *ptr) {
  return sizeof(atomic_ruby_condition_variable_waiter_t);
}

static void atomic_ruby_condition_variable_waiter_compact(void *ptr) {
  atomic_ruby_condition_variable_waiter_t *atomic_ruby_condition_variable_waiter = (atomic_ruby_condition_variable_waiter_t *)ptr;
  atomic_ruby_condition_variable_waiter->prev = rb_gc_location(atomic_ruby_condition_variable_waiter->prev);
  atomic_ruby_condition_variable_waiter->next = rb_gc_location(atomic_ruby_condition_variable_waiter->next);
  atomic_ruby_condition_variable_waiter->thread = rb_gc_location(atomic_ruby_condition_variable_waiter->thread);
}

static const rb_data_type_t atomic_ruby_condition_variable_waiter_type = {
  .wrap_struct_name = "AtomicRuby::AtomicConditionVariable::Waiter",
  .function = {
    .dmark = atomic_ruby_condition_variable_waiter_mark,
    .dfree = atomic_ruby_condition_variable_waiter_free,
    .dsize = atomic_ruby_condition_variable_waiter_memsize,
    .dcompact = atomic_ruby_condition_variable_waiter_compact
  },
  .flags = RUBY_TYPED_FREE_IMMEDIATELY | RUBY_TYPED_WB_PROTECTED
};

static VALUE rb_cAtomicConditionVariableWaiter;

static VALUE atomic_ruby_condition_variable_waiter_new(VALUE thread) {
  atomic_ruby_condition_variable_waiter_t *atomic_ruby_condition_variable_waiter;
  VALUE obj = TypedData_Make_Struct(rb_cAtomicConditionVariableWaiter, atomic_ruby_condition_variable_waiter_t, &atomic_ruby_condition_variable_waiter_type, atomic_ruby_condition_variable_waiter);
  RB_OBJ_WRITE(obj, &atomic_ruby_condition_variable_waiter->prev, Qnil);
  RB_OBJ_WRITE(obj, &atomic_ruby_condition_variable_waiter->next, Qnil);
  RB_OBJ_WRITE(obj, &atomic_ruby_condition_variable_waiter->thread, thread);
  return obj;
}

typedef struct {
  volatile VALUE head;
  volatile VALUE tail;
  volatile rb_atomic_t count;
} atomic_ruby_condition_variable_t;

static void atomic_ruby_condition_variable_mark(void *ptr) {
  atomic_ruby_condition_variable_t *atomic_ruby_condition_variable = (atomic_ruby_condition_variable_t *)ptr;
  rb_gc_mark_movable(atomic_ruby_condition_variable->head);
  rb_gc_mark_movable(atomic_ruby_condition_variable->tail);
}

static void atomic_ruby_condition_variable_free(void *ptr) {
  xfree(ptr);
}

static size_t atomic_ruby_condition_variable_memsize(const void *ptr) {
  return sizeof(atomic_ruby_condition_variable_t);
}

static void atomic_ruby_condition_variable_compact(void *ptr) {
  atomic_ruby_condition_variable_t *atomic_ruby_condition_variable = (atomic_ruby_condition_variable_t *)ptr;
  atomic_ruby_condition_variable->head = rb_gc_location(atomic_ruby_condition_variable->head);
  atomic_ruby_condition_variable->tail = rb_gc_location(atomic_ruby_condition_variable->tail);
}

static const rb_data_type_t atomic_ruby_condition_variable_type = {
  .wrap_struct_name = "AtomicRuby::AtomicConditionVariable",
  .function = {
    .dmark = atomic_ruby_condition_variable_mark,
    .dfree = atomic_ruby_condition_variable_free,
    .dsize = atomic_ruby_condition_variable_memsize,
    .dcompact = atomic_ruby_condition_variable_compact
  },
  .flags = RUBY_TYPED_FREE_IMMEDIATELY | RUBY_TYPED_WB_PROTECTED
};

static VALUE rb_cAtomicConditionVariable_allocate(VALUE klass) {
  atomic_ruby_condition_variable_t *atomic_ruby_condition_variable;
  VALUE obj = TypedData_Make_Struct(klass, atomic_ruby_condition_variable_t, &atomic_ruby_condition_variable_type, atomic_ruby_condition_variable);
  RB_OBJ_WRITE(obj, &atomic_ruby_condition_variable->head, Qnil);
  RB_OBJ_WRITE(obj, &atomic_ruby_condition_variable->tail, Qnil);
  atomic_ruby_condition_variable->count = 0;
  return obj;
}

static VALUE rb_cAtomicConditionVariable_initialize(VALUE self) {
  return self;
}

static VALUE rb_cAtomicConditionVariable_add_waiter(VALUE self, VALUE thread) {
  atomic_ruby_condition_variable_t *atomic_ruby_condition_variable;
  TypedData_Get_Struct(self, atomic_ruby_condition_variable_t, &atomic_ruby_condition_variable_type, atomic_ruby_condition_variable);

  VALUE new_waiter = atomic_ruby_condition_variable_waiter_new(thread);
  atomic_ruby_condition_variable_waiter_t *new_waiter_data;
  TypedData_Get_Struct(new_waiter, atomic_ruby_condition_variable_waiter_t, &atomic_ruby_condition_variable_waiter_type, new_waiter_data);

  VALUE tail = atomic_ruby_condition_variable->tail;
  if (tail == Qnil) {
    RB_OBJ_WRITE(self, &atomic_ruby_condition_variable->head, new_waiter);
    RB_OBJ_WRITE(self, &atomic_ruby_condition_variable->tail, new_waiter);
  } else {
    atomic_ruby_condition_variable_waiter_t *tail_data;
    TypedData_Get_Struct(tail, atomic_ruby_condition_variable_waiter_t, &atomic_ruby_condition_variable_waiter_type, tail_data);
    RB_OBJ_WRITE(tail, &tail_data->next, new_waiter);
    RB_OBJ_WRITE(new_waiter, &new_waiter_data->prev, tail);
    RB_OBJ_WRITE(self, &atomic_ruby_condition_variable->tail, new_waiter);
  }
  RUBY_ATOMIC_INC(atomic_ruby_condition_variable->count);

  return new_waiter;
}

static VALUE rb_cAtomicConditionVariable_remove_waiter(VALUE self, VALUE waiter) {
  atomic_ruby_condition_variable_t *atomic_ruby_condition_variable;
  TypedData_Get_Struct(self, atomic_ruby_condition_variable_t, &atomic_ruby_condition_variable_type, atomic_ruby_condition_variable);
  atomic_ruby_condition_variable_waiter_t *waiter_data;
  TypedData_Get_Struct(waiter, atomic_ruby_condition_variable_waiter_t, &atomic_ruby_condition_variable_waiter_type, waiter_data);

  VALUE prev = waiter_data->prev;
  VALUE next = waiter_data->next;

  if (prev == Qnil && next == Qnil && atomic_ruby_condition_variable->head != waiter) return Qnil;

  if (prev == Qnil) {
    RB_OBJ_WRITE(self, &atomic_ruby_condition_variable->head, next);
  } else {
    atomic_ruby_condition_variable_waiter_t *prev_data;
    TypedData_Get_Struct(prev, atomic_ruby_condition_variable_waiter_t, &atomic_ruby_condition_variable_waiter_type, prev_data);
    RB_OBJ_WRITE(prev, &prev_data->next, next);
  }

  if (next == Qnil) {
    RB_OBJ_WRITE(self, &atomic_ruby_condition_variable->tail, prev);
  } else {
    atomic_ruby_condition_variable_waiter_t *next_data;
    TypedData_Get_Struct(next, atomic_ruby_condition_variable_waiter_t, &atomic_ruby_condition_variable_waiter_type, next_data);
    RB_OBJ_WRITE(next, &next_data->prev, prev);
  }

  RB_OBJ_WRITE(waiter, &waiter_data->prev, Qnil);
  RB_OBJ_WRITE(waiter, &waiter_data->next, Qnil);
  RUBY_ATOMIC_DEC(atomic_ruby_condition_variable->count);

  return Qnil;
}

static VALUE rb_cAtomicConditionVariable_shift_thread(VALUE self) {
  atomic_ruby_condition_variable_t *atomic_ruby_condition_variable;
  TypedData_Get_Struct(self, atomic_ruby_condition_variable_t, &atomic_ruby_condition_variable_type, atomic_ruby_condition_variable);

  VALUE head = atomic_ruby_condition_variable->head;
  if (head == Qnil) return Qnil;

  atomic_ruby_condition_variable_waiter_t *head_data;
  TypedData_Get_Struct(head, atomic_ruby_condition_variable_waiter_t, &atomic_ruby_condition_variable_waiter_type, head_data);
  VALUE thread = head_data->thread;
  VALUE next = head_data->next;

  RB_OBJ_WRITE(self, &atomic_ruby_condition_variable->head, next);
  if (next == Qnil) {
    RB_OBJ_WRITE(self, &atomic_ruby_condition_variable->tail, Qnil);
  } else {
    atomic_ruby_condition_variable_waiter_t *next_data;
    TypedData_Get_Struct(next, atomic_ruby_condition_variable_waiter_t, &atomic_ruby_condition_variable_waiter_type, next_data);
    RB_OBJ_WRITE(next, &next_data->prev, Qnil);
  }

  RB_OBJ_WRITE(head, &head_data->prev, Qnil);
  RB_OBJ_WRITE(head, &head_data->next, Qnil);
  RUBY_ATOMIC_DEC(atomic_ruby_condition_variable->count);

  return thread;
}

static VALUE rb_cAtomicConditionVariable_drain_threads(VALUE self) {
  atomic_ruby_condition_variable_t *atomic_ruby_condition_variable;
  TypedData_Get_Struct(self, atomic_ruby_condition_variable_t, &atomic_ruby_condition_variable_type, atomic_ruby_condition_variable);

  VALUE threads = rb_ary_new();
  VALUE current = atomic_ruby_condition_variable->head;
  while (current != Qnil) {
    atomic_ruby_condition_variable_waiter_t *waiter_data;
    TypedData_Get_Struct(current, atomic_ruby_condition_variable_waiter_t, &atomic_ruby_condition_variable_waiter_type, waiter_data);
    rb_ary_push(threads, waiter_data->thread);
    VALUE next = waiter_data->next;
    RB_OBJ_WRITE(current, &waiter_data->prev, Qnil);
    RB_OBJ_WRITE(current, &waiter_data->next, Qnil);
    current = next;
  }
  RB_OBJ_WRITE(self, &atomic_ruby_condition_variable->head, Qnil);
  RB_OBJ_WRITE(self, &atomic_ruby_condition_variable->tail, Qnil);
  atomic_ruby_condition_variable->count = 0;

  return threads;
}

static VALUE rb_cAtomicConditionVariable_waiter_count(VALUE self) {
  atomic_ruby_condition_variable_t *atomic_ruby_condition_variable;
  TypedData_Get_Struct(self, atomic_ruby_condition_variable_t, &atomic_ruby_condition_variable_type, atomic_ruby_condition_variable);
  return UINT2NUM((unsigned int)RUBY_ATOMIC_LOAD(atomic_ruby_condition_variable->count));
}

typedef enum {
  ATOMIC_RUBY_THREAD_POOL_WORKER_INACTIVE,
  ATOMIC_RUBY_THREAD_POOL_WORKER_RUNNING,
  ATOMIC_RUBY_THREAD_POOL_WORKER_WAITING,
  ATOMIC_RUBY_THREAD_POOL_WORKER_BLOCKED
} atomic_ruby_thread_pool_worker_phase_t;

typedef struct {
  _Atomic unsigned int running_count;
  _Atomic unsigned int waiting_count;
  _Atomic unsigned int blocked_count;
  _Atomic unsigned long long running_time;
  _Atomic unsigned long long waiting_time;
  _Atomic unsigned long long blocked_time;
} atomic_ruby_thread_pool_monitor_t;

typedef struct {
  atomic_ruby_thread_pool_monitor_t *monitor;
  atomic_ruby_thread_pool_worker_phase_t phase;
  unsigned long long phase_started_at;
} atomic_ruby_thread_pool_worker_state_t;

static rb_internal_thread_specific_key_t atomic_ruby_thread_pool_worker_key;

static void atomic_ruby_thread_pool_monitor_free(void *ptr) {
  xfree(ptr);
}

static size_t atomic_ruby_thread_pool_monitor_memsize(const void *ptr) {
  return sizeof(atomic_ruby_thread_pool_monitor_t);
}

static const rb_data_type_t atomic_ruby_thread_pool_monitor_type = {
  .wrap_struct_name = "AtomicRuby::ThreadPoolMonitor",
  .function = {
    .dfree = atomic_ruby_thread_pool_monitor_free,
    .dsize = atomic_ruby_thread_pool_monitor_memsize
  },
  .flags = RUBY_TYPED_FREE_IMMEDIATELY | RUBY_TYPED_WB_PROTECTED
};

static unsigned long long atomic_ruby_monotonic_time(void) {
  struct timespec time;
  if (clock_gettime(CLOCK_MONOTONIC, &time) == -1) return 0;

  return (unsigned long long)time.tv_sec * 1000000000ULL + (unsigned long long)time.tv_nsec;
}

static void atomic_ruby_thread_pool_worker_leave_phase(atomic_ruby_thread_pool_worker_state_t *state, unsigned long long now) {
  unsigned long long elapsed = now != 0 && state->phase_started_at != 0 && now >= state->phase_started_at ? now - state->phase_started_at : 0;

  switch (state->phase) {
    case ATOMIC_RUBY_THREAD_POOL_WORKER_RUNNING:
      atomic_fetch_sub_explicit(&state->monitor->running_count, 1, memory_order_relaxed);
      atomic_fetch_add_explicit(&state->monitor->running_time, elapsed, memory_order_relaxed);
      break;
    case ATOMIC_RUBY_THREAD_POOL_WORKER_WAITING:
      atomic_fetch_sub_explicit(&state->monitor->waiting_count, 1, memory_order_relaxed);
      atomic_fetch_add_explicit(&state->monitor->waiting_time, elapsed, memory_order_relaxed);
      break;
    case ATOMIC_RUBY_THREAD_POOL_WORKER_BLOCKED:
      atomic_fetch_sub_explicit(&state->monitor->blocked_count, 1, memory_order_relaxed);
      atomic_fetch_add_explicit(&state->monitor->blocked_time, elapsed, memory_order_relaxed);
      break;
    case ATOMIC_RUBY_THREAD_POOL_WORKER_INACTIVE:
      break;
  }
}

static void atomic_ruby_thread_pool_worker_enter_phase(atomic_ruby_thread_pool_worker_state_t *state, atomic_ruby_thread_pool_worker_phase_t phase, unsigned long long now) {
  state->phase = phase;
  state->phase_started_at = now;

  switch (phase) {
    case ATOMIC_RUBY_THREAD_POOL_WORKER_RUNNING:
      atomic_fetch_add_explicit(&state->monitor->running_count, 1, memory_order_relaxed);
      break;
    case ATOMIC_RUBY_THREAD_POOL_WORKER_WAITING:
      atomic_fetch_add_explicit(&state->monitor->waiting_count, 1, memory_order_relaxed);
      break;
    case ATOMIC_RUBY_THREAD_POOL_WORKER_BLOCKED:
      atomic_fetch_add_explicit(&state->monitor->blocked_count, 1, memory_order_relaxed);
      break;
    case ATOMIC_RUBY_THREAD_POOL_WORKER_INACTIVE:
      break;
  }
}

static void atomic_ruby_thread_pool_event_callback(rb_event_flag_t event, const rb_internal_thread_event_data_t *event_data, void *user_data) {
  atomic_ruby_thread_pool_worker_state_t *state = rb_internal_thread_specific_get(event_data->thread, atomic_ruby_thread_pool_worker_key);
  if (state == NULL || state->phase == ATOMIC_RUBY_THREAD_POOL_WORKER_INACTIVE) return;

  unsigned long long now = atomic_ruby_monotonic_time();
  atomic_ruby_thread_pool_worker_leave_phase(state, now);

  switch (event) {
    case RUBY_INTERNAL_THREAD_EVENT_READY:
      atomic_ruby_thread_pool_worker_enter_phase(state, ATOMIC_RUBY_THREAD_POOL_WORKER_WAITING, now);
      break;
    case RUBY_INTERNAL_THREAD_EVENT_RESUMED:
      atomic_ruby_thread_pool_worker_enter_phase(state, ATOMIC_RUBY_THREAD_POOL_WORKER_RUNNING, now);
      break;
    case RUBY_INTERNAL_THREAD_EVENT_SUSPENDED:
      atomic_ruby_thread_pool_worker_enter_phase(state, ATOMIC_RUBY_THREAD_POOL_WORKER_BLOCKED, now);
      break;
  }
}

static VALUE rb_cThreadPoolMonitor_allocate(VALUE klass) {
  atomic_ruby_thread_pool_monitor_t *monitor;
  VALUE obj = TypedData_Make_Struct(klass, atomic_ruby_thread_pool_monitor_t, &atomic_ruby_thread_pool_monitor_type, monitor);
  atomic_init(&monitor->running_count, 0);
  atomic_init(&monitor->waiting_count, 0);
  atomic_init(&monitor->blocked_count, 0);
  atomic_init(&monitor->running_time, 0);
  atomic_init(&monitor->waiting_time, 0);
  atomic_init(&monitor->blocked_time, 0);
  return obj;
}

static VALUE rb_cThreadPoolMonitor_register_worker(VALUE self) {
  atomic_ruby_thread_pool_monitor_t *monitor;
  TypedData_Get_Struct(self, atomic_ruby_thread_pool_monitor_t, &atomic_ruby_thread_pool_monitor_type, monitor);

  VALUE thread = rb_thread_current();
  atomic_ruby_thread_pool_worker_state_t *state = ALLOC(atomic_ruby_thread_pool_worker_state_t);
  state->monitor = monitor;
  state->phase = ATOMIC_RUBY_THREAD_POOL_WORKER_INACTIVE;
  state->phase_started_at = 0;
  rb_internal_thread_specific_set(thread, atomic_ruby_thread_pool_worker_key, state);
  return Qnil;
}

static VALUE rb_cThreadPoolMonitor_unregister_worker(VALUE self) {
  VALUE thread = rb_thread_current();
  atomic_ruby_thread_pool_worker_state_t *state = rb_internal_thread_specific_get(thread, atomic_ruby_thread_pool_worker_key);
  if (state == NULL) return Qnil;

  atomic_ruby_thread_pool_worker_leave_phase(state, atomic_ruby_monotonic_time());
  rb_internal_thread_specific_set(thread, atomic_ruby_thread_pool_worker_key, NULL);
  xfree(state);
  return Qnil;
}

static VALUE rb_cThreadPoolMonitor_start_work(VALUE self) {
  atomic_ruby_thread_pool_worker_state_t *state = rb_internal_thread_specific_get(rb_thread_current(), atomic_ruby_thread_pool_worker_key);
  atomic_ruby_thread_pool_worker_enter_phase(state, ATOMIC_RUBY_THREAD_POOL_WORKER_RUNNING, atomic_ruby_monotonic_time());
  return Qnil;
}

static VALUE rb_cThreadPoolMonitor_stop_work(VALUE self) {
  atomic_ruby_thread_pool_worker_state_t *state = rb_internal_thread_specific_get(rb_thread_current(), atomic_ruby_thread_pool_worker_key);
  atomic_ruby_thread_pool_worker_leave_phase(state, atomic_ruby_monotonic_time());
  state->phase = ATOMIC_RUBY_THREAD_POOL_WORKER_INACTIVE;
  return Qnil;
}

static VALUE rb_cThreadPoolMonitor_snapshot(VALUE self) {
  atomic_ruby_thread_pool_monitor_t *monitor;
  TypedData_Get_Struct(self, atomic_ruby_thread_pool_monitor_t, &atomic_ruby_thread_pool_monitor_type, monitor);

  return rb_ary_new_from_args(
    6,
    UINT2NUM(atomic_load_explicit(&monitor->running_count, memory_order_relaxed)),
    UINT2NUM(atomic_load_explicit(&monitor->waiting_count, memory_order_relaxed)),
    UINT2NUM(atomic_load_explicit(&monitor->blocked_count, memory_order_relaxed)),
    ULL2NUM(atomic_load_explicit(&monitor->running_time, memory_order_relaxed)),
    ULL2NUM(atomic_load_explicit(&monitor->waiting_time, memory_order_relaxed)),
    ULL2NUM(atomic_load_explicit(&monitor->blocked_time, memory_order_relaxed))
  );
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

  VALUE rb_cAtomicConditionVariable = rb_define_class_under(rb_mAtomicRuby, "AtomicConditionVariable", rb_cObject);
  rb_cAtomicConditionVariableWaiter = rb_define_class_under(rb_cAtomicConditionVariable, "Waiter", rb_cObject);
  rb_undef_alloc_func(rb_cAtomicConditionVariableWaiter);

  rb_define_alloc_func(rb_cAtomicConditionVariable, rb_cAtomicConditionVariable_allocate);
  rb_define_private_method(rb_cAtomicConditionVariable, "_initialize", rb_cAtomicConditionVariable_initialize, 0);
  rb_define_private_method(rb_cAtomicConditionVariable, "_add_waiter", rb_cAtomicConditionVariable_add_waiter, 1);
  rb_define_private_method(rb_cAtomicConditionVariable, "_remove_waiter", rb_cAtomicConditionVariable_remove_waiter, 1);
  rb_define_private_method(rb_cAtomicConditionVariable, "_shift_thread", rb_cAtomicConditionVariable_shift_thread, 0);
  rb_define_private_method(rb_cAtomicConditionVariable, "_drain_threads", rb_cAtomicConditionVariable_drain_threads, 0);
  rb_define_private_method(rb_cAtomicConditionVariable, "_waiter_count", rb_cAtomicConditionVariable_waiter_count, 0);

  atomic_ruby_thread_pool_worker_key = rb_internal_thread_specific_key_create();
  rb_internal_thread_add_event_hook(
    atomic_ruby_thread_pool_event_callback,
    RUBY_INTERNAL_THREAD_EVENT_READY |
      RUBY_INTERNAL_THREAD_EVENT_RESUMED |
      RUBY_INTERNAL_THREAD_EVENT_SUSPENDED,
    NULL
  );
  VALUE rb_cThreadPoolMonitor = rb_define_class_under(rb_mAtomicRuby, "ThreadPoolMonitor", rb_cObject);
  rb_define_alloc_func(rb_cThreadPoolMonitor, rb_cThreadPoolMonitor_allocate);
  rb_define_method(rb_cThreadPoolMonitor, "register_worker", rb_cThreadPoolMonitor_register_worker, 0);
  rb_define_method(rb_cThreadPoolMonitor, "unregister_worker", rb_cThreadPoolMonitor_unregister_worker, 0);
  rb_define_method(rb_cThreadPoolMonitor, "start_work", rb_cThreadPoolMonitor_start_work, 0);
  rb_define_method(rb_cThreadPoolMonitor, "stop_work", rb_cThreadPoolMonitor_stop_work, 0);
  rb_define_method(rb_cThreadPoolMonitor, "snapshot", rb_cThreadPoolMonitor_snapshot, 0);
  rb_funcall(rb_mAtomicRuby, rb_intern("private_constant"), 1, ID2SYM(rb_intern("ThreadPoolMonitor")));
}
