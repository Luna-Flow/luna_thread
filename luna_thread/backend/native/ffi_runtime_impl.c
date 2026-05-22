#include "../../../native/include/luna_thread_runtime.h"

#include <limits.h>
#include <pthread.h>
#include <stdlib.h>
#include <string.h>
#include <stddef.h>
#include <stdint.h>

#if defined(LUNA_THREAD_HAVE_OPENMP) || defined(_OPENMP)
#include <omp.h>
#endif

typedef struct {
  int start;
  int end;
} luna_thread_chunk;

typedef enum {
  LUNA_THREAD_NODE_EXEC_COMPLETED = 0,
  LUNA_THREAD_NODE_EXEC_BLOCKED = 1,
  LUNA_THREAD_NODE_EXEC_FAILED = 2,
} luna_thread_node_exec_kind;

typedef struct {
  luna_thread_node_exec_kind kind;
  luna_thread_status status;
} luna_thread_node_exec_result;

typedef struct {
  const luna_thread_workflow_request *req;
  int *remaining_deps;
  int *enqueued;
  int *completed;
  int *node_blocked;
  int *node_signaled;
  int *node_depth;
  int completed_nodes;
  int failed_node_id;
  int *channel_has_value;
  int *mutex_locked;
  int *barrier_waiting;
  int *barrier_target;
  int *condvar_waiting;
  int compute_node_ready;
  int compute_node_index;
  int scheduler_shutdown;
  int scheduler_active;
  int compute_done;
  luna_thread_status compute_status;
  luna_thread_workflow_state state;
  luna_thread_status status;
  pthread_mutex_t mutex;
  pthread_cond_t cond;
  pthread_cond_t compute_cond;
  int *ready_queue;
  int ready_head;
  int ready_tail;
  int ready_count;
} luna_thread_workflow_runtime;

struct luna_thread_workflow_handle {
  luna_thread_workflow_runtime runtime;
  pthread_t *workers;
  int worker_count;
  pthread_t compute_thread;
};

static int add_overflow_i32(int32_t lhs, int32_t rhs, int32_t *out) {
  if (rhs > 0 && lhs > INT32_MAX - rhs) {
    return 1;
  }
  if (rhs < 0 && lhs < INT32_MIN - rhs) {
    return 1;
  }
  *out = lhs + rhs;
  return 0;
}

static int add_overflow_i64(int64_t lhs, int64_t rhs, int64_t *out) {
  if (rhs > 0 && lhs > INT64_MAX - rhs) {
    return 1;
  }
  if (rhs < 0 && lhs < INT64_MIN - rhs) {
    return 1;
  }
  *out = lhs + rhs;
  return 0;
}

static luna_thread_status validate_request(const void *ptr, int length) {
  if (ptr == NULL) {
    return LUNA_THREAD_STATUS_NULL_POINTER;
  }
  if (length < 0) {
    return LUNA_THREAD_STATUS_INVALID_ARGUMENT;
  }
  return LUNA_THREAD_STATUS_OK;
}

static int workflow_indegree(
  const luna_thread_workflow_request *req,
  int node_id
) {
  int degree = 0;
  for (int i = 0; i < req->edge_count; i++) {
    if (req->edges[i].to == node_id) {
      degree += 1;
    }
  }
  return degree;
}

static int workflow_node_index(
  const luna_thread_workflow_request *req,
  int node_id
) {
  for (int i = 0; i < req->node_count; i++) {
    if (req->nodes[i].id == node_id) {
      return i;
    }
  }
  return -1;
}

static int workflow_capability_index(
  const luna_thread_workflow_request *req,
  int capability_id
) {
  for (int i = 0; i < req->capability_count; i++) {
    if (req->capabilities[i].id == capability_id) {
      return i;
    }
  }
  return -1;
}

static void workflow_compute_node_depths(
  luna_thread_workflow_runtime *runtime
) {
  for (int i = 0; i < runtime->req->node_count; i++) {
    runtime->node_depth[i] = 0;
  }
  for (int pass = 0; pass < runtime->req->node_count; pass++) {
    for (int i = 0; i < runtime->req->edge_count; i++) {
      int from = workflow_node_index(runtime->req, runtime->req->edges[i].from);
      int to = workflow_node_index(runtime->req, runtime->req->edges[i].to);
      if (from >= 0 && to >= 0 &&
          runtime->node_depth[to] < runtime->node_depth[from] + 1) {
        runtime->node_depth[to] = runtime->node_depth[from] + 1;
      }
    }
  }
}

static int workflow_barrier_group_size(
  luna_thread_workflow_runtime *runtime,
  int capability_id,
  int depth
) {
  int total = 0;
  for (int i = 0; i < runtime->req->node_count; i++) {
    luna_thread_workflow_node node = runtime->req->nodes[i];
    if (node.kind == LUNA_THREAD_WORKFLOW_NODE_BARRIER &&
        node.capability_id == capability_id &&
        runtime->node_depth[i] == depth) {
      total += 1;
    }
  }
  if (total < 2) {
    return 0;
  }
  return total;
}

static void workflow_publish_failure(
  luna_thread_workflow_runtime *runtime,
  luna_thread_status status,
  int node_id
) {
  if (runtime->state == LUNA_THREAD_WORKFLOW_STATE_FAILED ||
      runtime->state == LUNA_THREAD_WORKFLOW_STATE_COMPLETED) {
    return;
  }
  runtime->status = status;
  runtime->failed_node_id = node_id;
  runtime->state = LUNA_THREAD_WORKFLOW_STATE_FAILED;
  runtime->scheduler_shutdown = 1;
  pthread_cond_broadcast(&runtime->cond);
  pthread_cond_broadcast(&runtime->compute_cond);
}

static void workflow_enqueue_ready(
  luna_thread_workflow_runtime *runtime,
  int node_index
) {
  if (runtime->enqueued[node_index] || runtime->completed[node_index]) {
    return;
  }
  runtime->ready_queue[runtime->ready_tail] = node_index;
  runtime->ready_tail = (runtime->ready_tail + 1) % runtime->req->node_count;
  runtime->ready_count += 1;
  runtime->enqueued[node_index] = 1;
  pthread_cond_signal(&runtime->cond);
}

static int workflow_dequeue_ready(
  luna_thread_workflow_runtime *runtime
) {
  if (runtime->ready_count == 0) {
    return -1;
  }
  int node_index = runtime->ready_queue[runtime->ready_head];
  runtime->ready_head = (runtime->ready_head + 1) % runtime->req->node_count;
  runtime->ready_count -= 1;
  runtime->enqueued[node_index] = 0;
  return node_index;
}

static void workflow_mark_completed(
  luna_thread_workflow_runtime *runtime,
  int node_index
) {
  if (runtime->completed[node_index]) {
    return;
  }
  runtime->completed[node_index] = 1;
  runtime->completed_nodes += 1;
  int node_id = runtime->req->nodes[node_index].id;
  for (int i = 0; i < runtime->req->edge_count; i++) {
    if (runtime->req->edges[i].from != node_id) {
      continue;
    }
    int target_index = workflow_node_index(runtime->req, runtime->req->edges[i].to);
    if (target_index >= 0) {
      runtime->remaining_deps[target_index] -= 1;
      if (runtime->remaining_deps[target_index] == 0) {
        workflow_enqueue_ready(runtime, target_index);
      }
    }
  }
  if (runtime->completed_nodes == runtime->req->node_count &&
      runtime->state != LUNA_THREAD_WORKFLOW_STATE_FAILED) {
    runtime->state = LUNA_THREAD_WORKFLOW_STATE_COMPLETED;
    runtime->status = LUNA_THREAD_STATUS_OK;
    runtime->scheduler_shutdown = 1;
    pthread_cond_broadcast(&runtime->cond);
    pthread_cond_broadcast(&runtime->compute_cond);
  }
}

static luna_thread_node_exec_result workflow_execute_simple_node(
  luna_thread_workflow_runtime *runtime,
  int node_index
) {
  luna_thread_workflow_node node = runtime->req->nodes[node_index];
  int cap_index = node.capability_id >= 0
    ? workflow_capability_index(runtime->req, node.capability_id)
    : -1;
  switch (node.kind) {
    case LUNA_THREAD_WORKFLOW_NODE_SPAWN:
    case LUNA_THREAD_WORKFLOW_NODE_JOIN:
      return (luna_thread_node_exec_result){ LUNA_THREAD_NODE_EXEC_COMPLETED, LUNA_THREAD_STATUS_OK };
    case LUNA_THREAD_WORKFLOW_NODE_SEND:
      if (runtime->channel_has_value[cap_index]) {
        runtime->node_blocked[node_index] = 1;
        return (luna_thread_node_exec_result){ LUNA_THREAD_NODE_EXEC_BLOCKED, LUNA_THREAD_STATUS_OK };
      }
      runtime->channel_has_value[cap_index] = 1;
      pthread_cond_broadcast(&runtime->cond);
      return (luna_thread_node_exec_result){ LUNA_THREAD_NODE_EXEC_COMPLETED, LUNA_THREAD_STATUS_OK };
    case LUNA_THREAD_WORKFLOW_NODE_RECV:
      if (!runtime->channel_has_value[cap_index]) {
        runtime->node_blocked[node_index] = 1;
        return (luna_thread_node_exec_result){ LUNA_THREAD_NODE_EXEC_BLOCKED, LUNA_THREAD_STATUS_OK };
      }
      runtime->channel_has_value[cap_index] = 0;
      pthread_cond_broadcast(&runtime->cond);
      return (luna_thread_node_exec_result){ LUNA_THREAD_NODE_EXEC_COMPLETED, LUNA_THREAD_STATUS_OK };
    case LUNA_THREAD_WORKFLOW_NODE_LOCK:
      if (runtime->mutex_locked[cap_index]) {
        runtime->node_blocked[node_index] = 1;
        return (luna_thread_node_exec_result){ LUNA_THREAD_NODE_EXEC_BLOCKED, LUNA_THREAD_STATUS_OK };
      }
      runtime->mutex_locked[cap_index] = 1;
      return (luna_thread_node_exec_result){ LUNA_THREAD_NODE_EXEC_COMPLETED, LUNA_THREAD_STATUS_OK };
    case LUNA_THREAD_WORKFLOW_NODE_UNLOCK:
      if (!runtime->mutex_locked[cap_index]) {
        return (luna_thread_node_exec_result){ LUNA_THREAD_NODE_EXEC_FAILED, LUNA_THREAD_STATUS_MUTEX_PROTOCOL_ERROR };
      }
      runtime->mutex_locked[cap_index] = 0;
      pthread_cond_broadcast(&runtime->cond);
      return (luna_thread_node_exec_result){ LUNA_THREAD_NODE_EXEC_COMPLETED, LUNA_THREAD_STATUS_OK };
    case LUNA_THREAD_WORKFLOW_NODE_WAIT:
      if (runtime->node_signaled[node_index]) {
        runtime->node_signaled[node_index] = 0;
        return (luna_thread_node_exec_result){ LUNA_THREAD_NODE_EXEC_COMPLETED, LUNA_THREAD_STATUS_OK };
      }
      if (runtime->req->capability_count == 0) {
        return (luna_thread_node_exec_result){ LUNA_THREAD_NODE_EXEC_FAILED, LUNA_THREAD_STATUS_CONDVAR_PROTOCOL_ERROR };
      }
      runtime->condvar_waiting[cap_index] += 1;
      runtime->node_blocked[node_index] = 1;
      return (luna_thread_node_exec_result){ LUNA_THREAD_NODE_EXEC_BLOCKED, LUNA_THREAD_STATUS_OK };
    case LUNA_THREAD_WORKFLOW_NODE_SIGNAL:
      for (int i = 0; i < runtime->req->node_count; i++) {
        if (!runtime->completed[i] &&
            runtime->node_blocked[i] &&
            runtime->req->nodes[i].kind == LUNA_THREAD_WORKFLOW_NODE_WAIT &&
            runtime->req->nodes[i].capability_id == node.capability_id) {
          runtime->node_blocked[i] = 0;
          runtime->node_signaled[i] = 1;
          runtime->condvar_waiting[cap_index] -= 1;
          workflow_enqueue_ready(runtime, i);
          break;
        }
      }
      pthread_cond_broadcast(&runtime->cond);
      return (luna_thread_node_exec_result){ LUNA_THREAD_NODE_EXEC_COMPLETED, LUNA_THREAD_STATUS_OK };
    case LUNA_THREAD_WORKFLOW_NODE_BARRIER:
      if (runtime->node_signaled[node_index]) {
        runtime->node_signaled[node_index] = 0;
        return (luna_thread_node_exec_result){ LUNA_THREAD_NODE_EXEC_COMPLETED, LUNA_THREAD_STATUS_OK };
      }
      {
        int depth = runtime->node_depth[node_index];
        int group_size = workflow_barrier_group_size(runtime, node.capability_id, depth);
        if (group_size <= 0) {
          return (luna_thread_node_exec_result){ LUNA_THREAD_NODE_EXEC_FAILED, LUNA_THREAD_STATUS_BARRIER_BROKEN };
        }
        runtime->barrier_target[cap_index] = group_size;
        runtime->barrier_waiting[cap_index] += 1;
        if (runtime->barrier_waiting[cap_index] < runtime->barrier_target[cap_index]) {
          runtime->node_blocked[node_index] = 1;
          return (luna_thread_node_exec_result){ LUNA_THREAD_NODE_EXEC_BLOCKED, LUNA_THREAD_STATUS_OK };
        }
        runtime->barrier_waiting[cap_index] = 0;
        for (int i = 0; i < runtime->req->node_count; i++) {
          if (!runtime->completed[i] &&
              runtime->node_blocked[i] &&
              runtime->req->nodes[i].kind == LUNA_THREAD_WORKFLOW_NODE_BARRIER &&
              runtime->req->nodes[i].capability_id == node.capability_id &&
              runtime->node_depth[i] == depth) {
            runtime->node_blocked[i] = 0;
            runtime->node_signaled[i] = 1;
            workflow_enqueue_ready(runtime, i);
          }
        }
        return (luna_thread_node_exec_result){ LUNA_THREAD_NODE_EXEC_COMPLETED, LUNA_THREAD_STATUS_OK };
      }
    case LUNA_THREAD_WORKFLOW_NODE_READ_SHARED:
    case LUNA_THREAD_WORKFLOW_NODE_WRITE_SHARED:
      return (luna_thread_node_exec_result){ LUNA_THREAD_NODE_EXEC_COMPLETED, LUNA_THREAD_STATUS_OK };
    default:
      return (luna_thread_node_exec_result){ LUNA_THREAD_NODE_EXEC_COMPLETED, LUNA_THREAD_STATUS_OK };
  }
}

static luna_thread_status workflow_execute_compute_node(
  luna_thread_workflow_runtime *runtime,
  int node_index
) {
  runtime->compute_node_index = node_index;
  runtime->compute_node_ready = 1;
  runtime->compute_done = 0;
  pthread_cond_signal(&runtime->compute_cond);
  while (!runtime->compute_done &&
         runtime->state != LUNA_THREAD_WORKFLOW_STATE_FAILED) {
    pthread_cond_wait(&runtime->cond, &runtime->mutex);
  }
  return runtime->compute_status;
}

static void *workflow_compute_lane_main(void *arg) {
  luna_thread_workflow_runtime *runtime = (luna_thread_workflow_runtime *)arg;
  pthread_mutex_lock(&runtime->mutex);
  while (!runtime->scheduler_shutdown || runtime->compute_node_ready) {
    while (!runtime->compute_node_ready && !runtime->scheduler_shutdown) {
      pthread_cond_wait(&runtime->compute_cond, &runtime->mutex);
    }
    if (!runtime->compute_node_ready && runtime->scheduler_shutdown) {
      break;
    }
    int node_index = runtime->compute_node_index;
    runtime->compute_node_ready = 0;
    luna_thread_status status = LUNA_THREAD_STATUS_OK;
    luna_thread_workflow_node node = runtime->req->nodes[node_index];
    if (node.kind != LUNA_THREAD_WORKFLOW_NODE_COMPUTE) {
      status = LUNA_THREAD_STATUS_INVALID_ARGUMENT;
    }
    runtime->compute_status = status;
    runtime->compute_done = 1;
    pthread_cond_broadcast(&runtime->cond);
  }
  pthread_mutex_unlock(&runtime->mutex);
  return NULL;
}

static void *workflow_worker_main(void *arg) {
  luna_thread_workflow_runtime *runtime = (luna_thread_workflow_runtime *)arg;
  pthread_mutex_lock(&runtime->mutex);
  while (!runtime->scheduler_shutdown) {
    while (runtime->ready_count == 0 && !runtime->scheduler_shutdown) {
      pthread_cond_wait(&runtime->cond, &runtime->mutex);
    }
    if (runtime->scheduler_shutdown) {
      break;
    }
    int node_index = workflow_dequeue_ready(runtime);
    if (node_index < 0) {
      continue;
    }
    runtime->state = LUNA_THREAD_WORKFLOW_STATE_RUNNING;
    luna_thread_workflow_node node = runtime->req->nodes[node_index];
    luna_thread_node_exec_result result;
    if (node.kind == LUNA_THREAD_WORKFLOW_NODE_COMPUTE) {
      luna_thread_status status = workflow_execute_compute_node(runtime, node_index);
      result = (luna_thread_node_exec_result){
        status == LUNA_THREAD_STATUS_OK
          ? LUNA_THREAD_NODE_EXEC_COMPLETED
          : LUNA_THREAD_NODE_EXEC_FAILED,
        status,
      };
    } else {
      result = workflow_execute_simple_node(runtime, node_index);
    }
    if (result.kind == LUNA_THREAD_NODE_EXEC_COMPLETED) {
      workflow_mark_completed(runtime, node_index);
    } else if (result.kind == LUNA_THREAD_NODE_EXEC_FAILED) {
      workflow_publish_failure(runtime, result.status, node.id);
    }
  }
  pthread_mutex_unlock(&runtime->mutex);
  return NULL;
}

static luna_thread_status workflow_runtime_start(
  luna_thread_workflow_handle *handle,
  const luna_thread_workflow_request *req
) {
  memset(handle, 0, sizeof(*handle));
  handle->runtime.req = req;
  handle->runtime.state = LUNA_THREAD_WORKFLOW_STATE_SUBMITTED;
  handle->runtime.status = LUNA_THREAD_STATUS_OK;
  handle->runtime.failed_node_id = -1;
  handle->runtime.remaining_deps = malloc((size_t)req->node_count * sizeof(int));
  handle->runtime.enqueued = calloc((size_t)req->node_count, sizeof(int));
  handle->runtime.completed = calloc((size_t)req->node_count, sizeof(int));
  handle->runtime.node_blocked = calloc((size_t)req->node_count, sizeof(int));
  handle->runtime.node_signaled = calloc((size_t)req->node_count, sizeof(int));
  handle->runtime.node_depth = calloc((size_t)req->node_count, sizeof(int));
  handle->runtime.ready_queue = malloc((size_t)req->node_count * sizeof(int));
  handle->runtime.channel_has_value = calloc((size_t)req->capability_count, sizeof(int));
  handle->runtime.mutex_locked = calloc((size_t)req->capability_count, sizeof(int));
  handle->runtime.barrier_waiting = calloc((size_t)req->capability_count, sizeof(int));
  handle->runtime.barrier_target = calloc((size_t)req->capability_count, sizeof(int));
  handle->runtime.condvar_waiting = calloc((size_t)req->capability_count, sizeof(int));
  handle->workers = malloc((size_t)req->worker_count * sizeof(pthread_t));
  if (handle->runtime.remaining_deps == NULL ||
      handle->runtime.enqueued == NULL ||
      handle->runtime.completed == NULL ||
      handle->runtime.node_blocked == NULL ||
      handle->runtime.node_signaled == NULL ||
      handle->runtime.node_depth == NULL ||
      handle->runtime.ready_queue == NULL ||
      handle->runtime.channel_has_value == NULL ||
      handle->runtime.mutex_locked == NULL ||
      handle->runtime.barrier_waiting == NULL ||
      handle->runtime.barrier_target == NULL ||
      handle->runtime.condvar_waiting == NULL ||
      handle->workers == NULL) {
    return LUNA_THREAD_STATUS_INVALID_ARGUMENT;
  }
  pthread_mutex_init(&handle->runtime.mutex, NULL);
  pthread_cond_init(&handle->runtime.cond, NULL);
  pthread_cond_init(&handle->runtime.compute_cond, NULL);
  workflow_compute_node_depths(&handle->runtime);
  for (int i = 0; i < req->node_count; i++) {
    handle->runtime.remaining_deps[i] = workflow_indegree(req, req->nodes[i].id);
    if (handle->runtime.remaining_deps[i] == 0) {
      workflow_enqueue_ready(&handle->runtime, i);
    }
  }
  handle->worker_count = req->worker_count;
  for (int i = 0; i < handle->worker_count; i++) {
    pthread_create(&handle->workers[i], NULL, workflow_worker_main, &handle->runtime);
  }
  pthread_create(&handle->compute_thread, NULL, workflow_compute_lane_main, &handle->runtime);
  return LUNA_THREAD_STATUS_OK;
}

static void workflow_runtime_stop(luna_thread_workflow_handle *handle) {
  if (handle == NULL) {
    return;
  }
  pthread_mutex_lock(&handle->runtime.mutex);
  handle->runtime.scheduler_shutdown = 1;
  pthread_cond_broadcast(&handle->runtime.cond);
  pthread_cond_broadcast(&handle->runtime.compute_cond);
  pthread_mutex_unlock(&handle->runtime.mutex);
  for (int i = 0; i < handle->worker_count; i++) {
    pthread_join(handle->workers[i], NULL);
  }
  pthread_join(handle->compute_thread, NULL);
  pthread_cond_destroy(&handle->runtime.cond);
  pthread_cond_destroy(&handle->runtime.compute_cond);
  pthread_mutex_destroy(&handle->runtime.mutex);
  free(handle->runtime.remaining_deps);
  free(handle->runtime.enqueued);
  free(handle->runtime.completed);
  free(handle->runtime.node_blocked);
  free(handle->runtime.node_signaled);
  free(handle->runtime.node_depth);
  free(handle->runtime.ready_queue);
  free(handle->runtime.channel_has_value);
  free(handle->runtime.mutex_locked);
  free(handle->runtime.barrier_waiting);
  free(handle->runtime.barrier_target);
  free(handle->runtime.condvar_waiting);
  free(handle->workers);
}

static int workflow_has_capability(
  const luna_thread_workflow_request *req,
  int capability_id,
  luna_thread_capability_kind *out_kind
) {
  for (int i = 0; i < req->capability_count; i++) {
    if (req->capabilities[i].id == capability_id) {
      if (out_kind != NULL) {
        *out_kind = req->capabilities[i].kind;
      }
      return 1;
    }
  }
  return 0;
}

static int workflow_has_node(
  const luna_thread_workflow_request *req,
  int node_id
) {
  for (int i = 0; i < req->node_count; i++) {
    if (req->nodes[i].id == node_id) {
      return 1;
    }
  }
  return 0;
}

static int workflow_node_needs_capability(
  luna_thread_workflow_node_kind kind
) {
  switch (kind) {
    case LUNA_THREAD_WORKFLOW_NODE_SEND:
    case LUNA_THREAD_WORKFLOW_NODE_RECV:
    case LUNA_THREAD_WORKFLOW_NODE_LOCK:
    case LUNA_THREAD_WORKFLOW_NODE_UNLOCK:
    case LUNA_THREAD_WORKFLOW_NODE_WAIT:
    case LUNA_THREAD_WORKFLOW_NODE_SIGNAL:
    case LUNA_THREAD_WORKFLOW_NODE_BARRIER:
    case LUNA_THREAD_WORKFLOW_NODE_READ_SHARED:
    case LUNA_THREAD_WORKFLOW_NODE_WRITE_SHARED:
      return 1;
    default:
      return 0;
  }
}

static int workflow_node_matches_capability(
  luna_thread_workflow_node_kind node_kind,
  luna_thread_capability_kind cap_kind
) {
  switch (node_kind) {
    case LUNA_THREAD_WORKFLOW_NODE_SEND:
    case LUNA_THREAD_WORKFLOW_NODE_RECV:
      return cap_kind == LUNA_THREAD_CAP_CHANNEL;
    case LUNA_THREAD_WORKFLOW_NODE_LOCK:
    case LUNA_THREAD_WORKFLOW_NODE_UNLOCK:
      return cap_kind == LUNA_THREAD_CAP_MUTEX;
    case LUNA_THREAD_WORKFLOW_NODE_WAIT:
    case LUNA_THREAD_WORKFLOW_NODE_SIGNAL:
      return cap_kind == LUNA_THREAD_CAP_CONDVAR;
    case LUNA_THREAD_WORKFLOW_NODE_BARRIER:
      return cap_kind == LUNA_THREAD_CAP_BARRIER;
    case LUNA_THREAD_WORKFLOW_NODE_READ_SHARED:
      return cap_kind == LUNA_THREAD_CAP_SHARED_READ_VIEW ||
             cap_kind == LUNA_THREAD_CAP_ATOMIC_CELL;
    case LUNA_THREAD_WORKFLOW_NODE_WRITE_SHARED:
      return cap_kind == LUNA_THREAD_CAP_ATOMIC_CELL ||
             cap_kind == LUNA_THREAD_CAP_OWNED_BUFFER;
    default:
      return 1;
  }
}

static int workflow_has_cycle(const luna_thread_workflow_request *req) {
  int visited = 0;
  int progressed = 1;
  int *pending = malloc((size_t)req->node_count * sizeof(int));
  if (pending == NULL) {
    return 1;
  }
  for (int i = 0; i < req->node_count; i++) {
    pending[i] = 1;
  }
  while (progressed) {
    progressed = 0;
    for (int i = 0; i < req->node_count; i++) {
      if (!pending[i]) {
        continue;
      }
      int node_id = req->nodes[i].id;
      int indegree = 0;
      for (int e = 0; e < req->edge_count; e++) {
        if (req->edges[e].to != node_id) {
          continue;
        }
        for (int j = 0; j < req->node_count; j++) {
          if (pending[j] && req->nodes[j].id == req->edges[e].from) {
            indegree += 1;
          }
        }
      }
      if (indegree == 0) {
        pending[i] = 0;
        visited += 1;
        progressed = 1;
      }
    }
  }
  free(pending);
  return visited != req->node_count;
}

static luna_thread_status validate_workflow(const luna_thread_workflow_request *req) {
  if (req == NULL) {
    return LUNA_THREAD_STATUS_NULL_POINTER;
  }
  if (req->worker_count <= 0 || req->node_count <= 0) {
    return LUNA_THREAD_STATUS_INVALID_ARGUMENT;
  }
  if ((req->capability_count > 0 && req->capabilities == NULL) ||
      (req->node_count > 0 && req->nodes == NULL) ||
      (req->edge_count > 0 && req->edges == NULL)) {
    return LUNA_THREAD_STATUS_NULL_POINTER;
  }
  for (int i = 0; i < req->capability_count; i++) {
    if (req->capabilities[i].kind == LUNA_THREAD_CAP_RWLOCK ||
        req->capabilities[i].kind == LUNA_THREAD_CAP_SEMAPHORE ||
        req->capabilities[i].kind == LUNA_THREAD_CAP_OPAQUE) {
      return LUNA_THREAD_STATUS_UNSUPPORTED_RUNTIME_PRIMITIVE;
    }
  }
  for (int i = 0; i < req->node_count; i++) {
    luna_thread_workflow_node node = req->nodes[i];
    if (workflow_node_needs_capability(node.kind)) {
      luna_thread_capability_kind kind;
      if (node.capability_id < 0 ||
          !workflow_has_capability(req, node.capability_id, &kind)) {
        return LUNA_THREAD_STATUS_INVALID_ARGUMENT;
      }
      if (!workflow_node_matches_capability(node.kind, kind)) {
        return LUNA_THREAD_STATUS_INVALID_ARGUMENT;
      }
    }
  }
  for (int e = 0; e < req->edge_count; e++) {
    if (req->edges[e].from == req->edges[e].to) {
      return LUNA_THREAD_STATUS_INVALID_ARGUMENT;
    }
    if (!workflow_has_node(req, req->edges[e].from) ||
        !workflow_has_node(req, req->edges[e].to)) {
      return LUNA_THREAD_STATUS_INVALID_ARGUMENT;
    }
  }
  if (workflow_has_cycle(req)) {
    return LUNA_THREAD_STATUS_RUNTIME_BROKEN;
  }
  return LUNA_THREAD_STATUS_OK;
}

static int ceil_div_int(int lhs, int rhs) {
  return (lhs + rhs - 1) / rhs;
}

static luna_thread_status validate_parallel_cover(int element_count, int worker_count, int chunk_size) {
  if (worker_count <= 0 || chunk_size <= 0 || element_count <= 0) {
    return LUNA_THREAD_STATUS_INVALID_ARGUMENT;
  }
  if (worker_count < ceil_div_int(element_count, chunk_size)) {
    return LUNA_THREAD_STATUS_INVALID_ARGUMENT;
  }
  return LUNA_THREAD_STATUS_OK;
}

static int chunk_count_for(int element_count, int worker_count, int chunk_size) {
  int from_chunk_size = ceil_div_int(element_count, chunk_size);
  return from_chunk_size < worker_count ? from_chunk_size : worker_count;
}

static void fill_chunks(
  luna_thread_chunk *chunks,
  int element_count,
  int worker_count,
  int chunk_size
) {
  int count = chunk_count_for(element_count, worker_count, chunk_size);
  int start = 0;
  for (int i = 0; i < count; i++) {
    int remaining = element_count - start;
    int remaining_chunks = count - i;
    int span = ceil_div_int(remaining, remaining_chunks);
    chunks[i].start = start;
    chunks[i].end = start + span;
    start += span;
  }
}

static luna_thread_status validate_map(const luna_thread_map_request *req) {
  if (req == NULL) {
    return LUNA_THREAD_STATUS_NULL_POINTER;
  }
  if (req->worker_count <= 0 || req->chunk_size <= 0 || req->element_count <= 0) {
    return LUNA_THREAD_STATUS_INVALID_ARGUMENT;
  }
  if (req->value_type != LUNA_THREAD_VALUE_I32 && req->value_type != LUNA_THREAD_VALUE_I64) {
    return LUNA_THREAD_STATUS_UNSUPPORTED_VALUE_TYPE;
  }
  luna_thread_status in_status = validate_request(req->input.ptr, req->input.length);
  if (in_status != LUNA_THREAD_STATUS_OK) {
    return in_status;
  }
  luna_thread_status out_status = validate_request(req->output.ptr, req->output.length);
  if (out_status != LUNA_THREAD_STATUS_OK) {
    return out_status;
  }
  if (req->input.length < req->element_count || req->output.length < req->element_count) {
    return LUNA_THREAD_STATUS_INVALID_ARGUMENT;
  }
  if (req->worker_count > req->element_count || req->chunk_size > req->element_count) {
    return LUNA_THREAD_STATUS_INVALID_ARGUMENT;
  }
  return validate_parallel_cover(req->element_count, req->worker_count, req->chunk_size);
}

static luna_thread_status validate_scan(const luna_thread_scan_request *req) {
  if (req == NULL) {
    return LUNA_THREAD_STATUS_NULL_POINTER;
  }
  if (req->worker_count <= 0 || req->chunk_size <= 0 || req->element_count <= 0) {
    return LUNA_THREAD_STATUS_INVALID_ARGUMENT;
  }
  if (req->value_type != LUNA_THREAD_VALUE_I32 && req->value_type != LUNA_THREAD_VALUE_I64) {
    return LUNA_THREAD_STATUS_UNSUPPORTED_VALUE_TYPE;
  }
  if (req->reduction_kernel != LUNA_THREAD_REDUCTION_SUM) {
    return LUNA_THREAD_STATUS_UNSUPPORTED_REDUCTION_KERNEL;
  }
  luna_thread_status in_status = validate_request(req->input.ptr, req->input.length);
  if (in_status != LUNA_THREAD_STATUS_OK) {
    return in_status;
  }
  luna_thread_status out_status = validate_request(req->output.ptr, req->output.length);
  if (out_status != LUNA_THREAD_STATUS_OK) {
    return out_status;
  }
  if (req->input.length < req->element_count || req->output.length < req->element_count) {
    return LUNA_THREAD_STATUS_INVALID_ARGUMENT;
  }
  if (req->worker_count > req->element_count || req->chunk_size > req->element_count) {
    return LUNA_THREAD_STATUS_INVALID_ARGUMENT;
  }
  return validate_parallel_cover(req->element_count, req->worker_count, req->chunk_size);
}

static int select_thread_count(int worker_count) {
#if defined(LUNA_THREAD_HAVE_OPENMP) || defined(_OPENMP)
  return worker_count;
#else
  (void)worker_count;
  return 1;
#endif
}

static luna_thread_status alloc_chunks(
  luna_thread_chunk **out_chunks,
  int element_count,
  int worker_count,
  int chunk_size
) {
  int count = chunk_count_for(element_count, worker_count, chunk_size);
  luna_thread_chunk *chunks = malloc((size_t)count * sizeof(luna_thread_chunk));
  if (chunks == NULL) {
    return LUNA_THREAD_STATUS_INVALID_ARGUMENT;
  }
  fill_chunks(chunks, element_count, worker_count, chunk_size);
  *out_chunks = chunks;
  return LUNA_THREAD_STATUS_OK;
}

static luna_thread_status validate_reduce(const luna_thread_reduce_request *req) {
  if (req == NULL) {
    return LUNA_THREAD_STATUS_NULL_POINTER;
  }
  if (req->worker_count <= 0 || req->chunk_size <= 0 || req->element_count <= 0) {
    return LUNA_THREAD_STATUS_INVALID_ARGUMENT;
  }
  if (req->value_type != LUNA_THREAD_VALUE_I32 && req->value_type != LUNA_THREAD_VALUE_I64) {
    return LUNA_THREAD_STATUS_UNSUPPORTED_VALUE_TYPE;
  }
  if (req->reduction_kernel != LUNA_THREAD_REDUCTION_SUM &&
      req->reduction_kernel != LUNA_THREAD_REDUCTION_MIN &&
      req->reduction_kernel != LUNA_THREAD_REDUCTION_MAX) {
    return LUNA_THREAD_STATUS_UNSUPPORTED_REDUCTION_KERNEL;
  }
  luna_thread_status in_status = validate_request(req->input.ptr, req->input.length);
  if (in_status != LUNA_THREAD_STATUS_OK) {
    return in_status;
  }
  luna_thread_status out_status = validate_request(req->output.ptr, req->output.length);
  if (out_status != LUNA_THREAD_STATUS_OK) {
    return out_status;
  }
  if (req->input.length < req->element_count || req->output.length < 1) {
    return LUNA_THREAD_STATUS_INVALID_ARGUMENT;
  }
  if (req->worker_count > req->element_count || req->chunk_size > req->element_count) {
    return LUNA_THREAD_STATUS_INVALID_ARGUMENT;
  }
  return validate_parallel_cover(req->element_count, req->worker_count, req->chunk_size);
}

static luna_thread_status map_i32(const luna_thread_map_request *req) {
  const int32_t *src = (const int32_t *)req->input.ptr;
  int32_t *dst = (int32_t *)req->output.ptr;
  int overflow = 0;
  int thread_count = select_thread_count(req->worker_count);
#pragma omp parallel for num_threads(thread_count) reduction(| : overflow) if(thread_count > 1)
  for (int i = 0; i < req->element_count; i++) {
    int32_t tmp;
    if (add_overflow_i32(src[i], src[i], &tmp)) {
      overflow = 1;
    }
  }
  if (overflow) {
    return LUNA_THREAD_STATUS_OVERFLOW;
  }
#pragma omp parallel for num_threads(thread_count) if(thread_count > 1)
  for (int i = 0; i < req->element_count; i++) {
    dst[i] = src[i] + src[i];
  }
  return LUNA_THREAD_STATUS_OK;
}

static luna_thread_status map_i64(const luna_thread_map_request *req) {
  const int64_t *src = (const int64_t *)req->input.ptr;
  int64_t *dst = (int64_t *)req->output.ptr;
  int overflow = 0;
  int thread_count = select_thread_count(req->worker_count);
#pragma omp parallel for num_threads(thread_count) reduction(| : overflow) if(thread_count > 1)
  for (int i = 0; i < req->element_count; i++) {
    int64_t tmp;
    if (add_overflow_i64(src[i], src[i], &tmp)) {
      overflow = 1;
    }
  }
  if (overflow) {
    return LUNA_THREAD_STATUS_OVERFLOW;
  }
#pragma omp parallel for num_threads(thread_count) if(thread_count > 1)
  for (int i = 0; i < req->element_count; i++) {
    dst[i] = src[i] + src[i];
  }
  return LUNA_THREAD_STATUS_OK;
}

static luna_thread_status reduce_sum_i32(const luna_thread_reduce_request *req) {
  const int32_t *src = (const int32_t *)req->input.ptr;
  luna_thread_chunk *chunks = NULL;
  luna_thread_status status = alloc_chunks(
    &chunks,
    req->element_count,
    req->worker_count,
    req->chunk_size
  );
  if (status != LUNA_THREAD_STATUS_OK) {
    return status;
  }
  int chunk_count = chunk_count_for(req->element_count, req->worker_count, req->chunk_size);
  int32_t *partials = malloc((size_t)chunk_count * sizeof(int32_t));
  if (partials == NULL) {
    free(chunks);
    return LUNA_THREAD_STATUS_INVALID_ARGUMENT;
  }
  int overflow = 0;
  int thread_count = select_thread_count(req->worker_count);
#pragma omp parallel for num_threads(thread_count) reduction(| : overflow) if(thread_count > 1)
  for (int i = 0; i < chunk_count; i++) {
    int32_t acc = 0;
    int32_t tmp;
    for (int j = chunks[i].start; j < chunks[i].end; j++) {
      if (add_overflow_i32(acc, src[j], &tmp)) {
        overflow = 1;
        break;
      }
      acc = tmp;
    }
    partials[i] = acc;
  }
  if (overflow) {
    free(partials);
    free(chunks);
    return LUNA_THREAD_STATUS_OVERFLOW;
  }
  int32_t acc = 0;
  for (int i = 0; i < chunk_count; i++) {
    int32_t tmp;
    if (add_overflow_i32(acc, partials[i], &tmp)) {
      free(partials);
      free(chunks);
      return LUNA_THREAD_STATUS_OVERFLOW;
    }
    acc = tmp;
  }
  *(int32_t *)req->output.ptr = acc;
  free(partials);
  free(chunks);
  return LUNA_THREAD_STATUS_OK;
}

static luna_thread_status reduce_sum_i64(const luna_thread_reduce_request *req) {
  const int64_t *src = (const int64_t *)req->input.ptr;
  luna_thread_chunk *chunks = NULL;
  luna_thread_status status = alloc_chunks(
    &chunks,
    req->element_count,
    req->worker_count,
    req->chunk_size
  );
  if (status != LUNA_THREAD_STATUS_OK) {
    return status;
  }
  int chunk_count = chunk_count_for(req->element_count, req->worker_count, req->chunk_size);
  int64_t *partials = malloc((size_t)chunk_count * sizeof(int64_t));
  if (partials == NULL) {
    free(chunks);
    return LUNA_THREAD_STATUS_INVALID_ARGUMENT;
  }
  int overflow = 0;
  int thread_count = select_thread_count(req->worker_count);
#pragma omp parallel for num_threads(thread_count) reduction(| : overflow) if(thread_count > 1)
  for (int i = 0; i < chunk_count; i++) {
    int64_t acc = 0;
    int64_t tmp;
    for (int j = chunks[i].start; j < chunks[i].end; j++) {
      if (add_overflow_i64(acc, src[j], &tmp)) {
        overflow = 1;
        break;
      }
      acc = tmp;
    }
    partials[i] = acc;
  }
  if (overflow) {
    free(partials);
    free(chunks);
    return LUNA_THREAD_STATUS_OVERFLOW;
  }
  int64_t acc = 0;
  for (int i = 0; i < chunk_count; i++) {
    int64_t tmp;
    if (add_overflow_i64(acc, partials[i], &tmp)) {
      free(partials);
      free(chunks);
      return LUNA_THREAD_STATUS_OVERFLOW;
    }
    acc = tmp;
  }
  *(int64_t *)req->output.ptr = acc;
  free(partials);
  free(chunks);
  return LUNA_THREAD_STATUS_OK;
}

static luna_thread_status reduce_min_i32(const luna_thread_reduce_request *req) {
  const int32_t *src = (const int32_t *)req->input.ptr;
  luna_thread_chunk *chunks = NULL;
  luna_thread_status status = alloc_chunks(
    &chunks,
    req->element_count,
    req->worker_count,
    req->chunk_size
  );
  if (status != LUNA_THREAD_STATUS_OK) {
    return status;
  }
  int chunk_count = chunk_count_for(req->element_count, req->worker_count, req->chunk_size);
  int32_t *partials = malloc((size_t)chunk_count * sizeof(int32_t));
  if (partials == NULL) {
    free(chunks);
    return LUNA_THREAD_STATUS_INVALID_ARGUMENT;
  }
  int thread_count = select_thread_count(req->worker_count);
#pragma omp parallel for num_threads(thread_count) if(thread_count > 1)
  for (int i = 0; i < chunk_count; i++) {
    int32_t acc = src[chunks[i].start];
    for (int j = chunks[i].start + 1; j < chunks[i].end; j++) {
      if (src[j] < acc) {
        acc = src[j];
      }
    }
    partials[i] = acc;
  }
  int32_t acc = partials[0];
  for (int i = 1; i < chunk_count; i++) {
    if (partials[i] < acc) {
      acc = partials[i];
    }
  }
  *(int32_t *)req->output.ptr = acc;
  free(partials);
  free(chunks);
  return LUNA_THREAD_STATUS_OK;
}

static luna_thread_status reduce_min_i64(const luna_thread_reduce_request *req) {
  const int64_t *src = (const int64_t *)req->input.ptr;
  luna_thread_chunk *chunks = NULL;
  luna_thread_status status = alloc_chunks(
    &chunks,
    req->element_count,
    req->worker_count,
    req->chunk_size
  );
  if (status != LUNA_THREAD_STATUS_OK) {
    return status;
  }
  int chunk_count = chunk_count_for(req->element_count, req->worker_count, req->chunk_size);
  int64_t *partials = malloc((size_t)chunk_count * sizeof(int64_t));
  if (partials == NULL) {
    free(chunks);
    return LUNA_THREAD_STATUS_INVALID_ARGUMENT;
  }
  int thread_count = select_thread_count(req->worker_count);
#pragma omp parallel for num_threads(thread_count) if(thread_count > 1)
  for (int i = 0; i < chunk_count; i++) {
    int64_t acc = src[chunks[i].start];
    for (int j = chunks[i].start + 1; j < chunks[i].end; j++) {
      if (src[j] < acc) {
        acc = src[j];
      }
    }
    partials[i] = acc;
  }
  int64_t acc = partials[0];
  for (int i = 1; i < chunk_count; i++) {
    if (partials[i] < acc) {
      acc = partials[i];
    }
  }
  *(int64_t *)req->output.ptr = acc;
  free(partials);
  free(chunks);
  return LUNA_THREAD_STATUS_OK;
}

static luna_thread_status reduce_max_i32(const luna_thread_reduce_request *req) {
  const int32_t *src = (const int32_t *)req->input.ptr;
  luna_thread_chunk *chunks = NULL;
  luna_thread_status status = alloc_chunks(
    &chunks,
    req->element_count,
    req->worker_count,
    req->chunk_size
  );
  if (status != LUNA_THREAD_STATUS_OK) {
    return status;
  }
  int chunk_count = chunk_count_for(req->element_count, req->worker_count, req->chunk_size);
  int32_t *partials = malloc((size_t)chunk_count * sizeof(int32_t));
  if (partials == NULL) {
    free(chunks);
    return LUNA_THREAD_STATUS_INVALID_ARGUMENT;
  }
  int thread_count = select_thread_count(req->worker_count);
#pragma omp parallel for num_threads(thread_count) if(thread_count > 1)
  for (int i = 0; i < chunk_count; i++) {
    int32_t acc = src[chunks[i].start];
    for (int j = chunks[i].start + 1; j < chunks[i].end; j++) {
      if (src[j] > acc) {
        acc = src[j];
      }
    }
    partials[i] = acc;
  }
  int32_t acc = partials[0];
  for (int i = 1; i < chunk_count; i++) {
    if (partials[i] > acc) {
      acc = partials[i];
    }
  }
  *(int32_t *)req->output.ptr = acc;
  free(partials);
  free(chunks);
  return LUNA_THREAD_STATUS_OK;
}

static luna_thread_status reduce_max_i64(const luna_thread_reduce_request *req) {
  const int64_t *src = (const int64_t *)req->input.ptr;
  luna_thread_chunk *chunks = NULL;
  luna_thread_status status = alloc_chunks(
    &chunks,
    req->element_count,
    req->worker_count,
    req->chunk_size
  );
  if (status != LUNA_THREAD_STATUS_OK) {
    return status;
  }
  int chunk_count = chunk_count_for(req->element_count, req->worker_count, req->chunk_size);
  int64_t *partials = malloc((size_t)chunk_count * sizeof(int64_t));
  if (partials == NULL) {
    free(chunks);
    return LUNA_THREAD_STATUS_INVALID_ARGUMENT;
  }
  int thread_count = select_thread_count(req->worker_count);
#pragma omp parallel for num_threads(thread_count) if(thread_count > 1)
  for (int i = 0; i < chunk_count; i++) {
    int64_t acc = src[chunks[i].start];
    for (int j = chunks[i].start + 1; j < chunks[i].end; j++) {
      if (src[j] > acc) {
        acc = src[j];
      }
    }
    partials[i] = acc;
  }
  int64_t acc = partials[0];
  for (int i = 1; i < chunk_count; i++) {
    if (partials[i] > acc) {
      acc = partials[i];
    }
  }
  *(int64_t *)req->output.ptr = acc;
  free(partials);
  free(chunks);
  return LUNA_THREAD_STATUS_OK;
}

static luna_thread_status scan_sum_i32(const luna_thread_scan_request *req) {
  const int32_t *src = (const int32_t *)req->input.ptr;
  int32_t *dst = (int32_t *)req->output.ptr;
  luna_thread_chunk *chunks = NULL;
  luna_thread_status status = alloc_chunks(
    &chunks,
    req->element_count,
    req->worker_count,
    req->chunk_size
  );
  if (status != LUNA_THREAD_STATUS_OK) {
    return status;
  }
  int chunk_count = chunk_count_for(req->element_count, req->worker_count, req->chunk_size);
  int32_t *summaries = malloc((size_t)chunk_count * sizeof(int32_t));
  int32_t *carries = malloc((size_t)chunk_count * sizeof(int32_t));
  if (summaries == NULL || carries == NULL) {
    free(carries);
    free(summaries);
    free(chunks);
    return LUNA_THREAD_STATUS_INVALID_ARGUMENT;
  }
  int overflow = 0;
  int thread_count = select_thread_count(req->worker_count);
#pragma omp parallel for num_threads(thread_count) reduction(| : overflow) if(thread_count > 1)
  for (int i = 0; i < chunk_count; i++) {
    int32_t acc = 0;
    int32_t tmp;
    for (int j = chunks[i].start; j < chunks[i].end; j++) {
      if (add_overflow_i32(acc, src[j], &tmp)) {
        overflow = 1;
        break;
      }
      acc = tmp;
      dst[j] = acc;
    }
    summaries[i] = acc;
  }
  if (overflow) {
    free(carries);
    free(summaries);
    free(chunks);
    return LUNA_THREAD_STATUS_OVERFLOW;
  }
  carries[0] = 0;
  for (int i = 1; i < chunk_count; i++) {
    int32_t tmp;
    if (add_overflow_i32(carries[i - 1], summaries[i - 1], &tmp)) {
      free(carries);
      free(summaries);
      free(chunks);
      return LUNA_THREAD_STATUS_OVERFLOW;
    }
    carries[i] = tmp;
  }
#pragma omp parallel for num_threads(thread_count) reduction(| : overflow) if(thread_count > 1)
  for (int i = 0; i < chunk_count; i++) {
    int32_t carry = carries[i];
    if (carry == 0) {
      continue;
    }
    for (int j = chunks[i].start; j < chunks[i].end; j++) {
      int32_t tmp;
      if (add_overflow_i32(dst[j], carry, &tmp)) {
        overflow = 1;
        break;
      }
      dst[j] = tmp;
    }
  }
  free(carries);
  free(summaries);
  free(chunks);
  if (overflow) {
    return LUNA_THREAD_STATUS_OVERFLOW;
  }
  return LUNA_THREAD_STATUS_OK;
}

static luna_thread_status scan_sum_i64(const luna_thread_scan_request *req) {
  const int64_t *src = (const int64_t *)req->input.ptr;
  int64_t *dst = (int64_t *)req->output.ptr;
  luna_thread_chunk *chunks = NULL;
  luna_thread_status status = alloc_chunks(
    &chunks,
    req->element_count,
    req->worker_count,
    req->chunk_size
  );
  if (status != LUNA_THREAD_STATUS_OK) {
    return status;
  }
  int chunk_count = chunk_count_for(req->element_count, req->worker_count, req->chunk_size);
  int64_t *summaries = malloc((size_t)chunk_count * sizeof(int64_t));
  int64_t *carries = malloc((size_t)chunk_count * sizeof(int64_t));
  if (summaries == NULL || carries == NULL) {
    free(carries);
    free(summaries);
    free(chunks);
    return LUNA_THREAD_STATUS_INVALID_ARGUMENT;
  }
  int overflow = 0;
  int thread_count = select_thread_count(req->worker_count);
#pragma omp parallel for num_threads(thread_count) reduction(| : overflow) if(thread_count > 1)
  for (int i = 0; i < chunk_count; i++) {
    int64_t acc = 0;
    int64_t tmp;
    for (int j = chunks[i].start; j < chunks[i].end; j++) {
      if (add_overflow_i64(acc, src[j], &tmp)) {
        overflow = 1;
        break;
      }
      acc = tmp;
      dst[j] = acc;
    }
    summaries[i] = acc;
  }
  if (overflow) {
    free(carries);
    free(summaries);
    free(chunks);
    return LUNA_THREAD_STATUS_OVERFLOW;
  }
  carries[0] = 0;
  for (int i = 1; i < chunk_count; i++) {
    int64_t tmp;
    if (add_overflow_i64(carries[i - 1], summaries[i - 1], &tmp)) {
      free(carries);
      free(summaries);
      free(chunks);
      return LUNA_THREAD_STATUS_OVERFLOW;
    }
    carries[i] = tmp;
  }
#pragma omp parallel for num_threads(thread_count) reduction(| : overflow) if(thread_count > 1)
  for (int i = 0; i < chunk_count; i++) {
    int64_t carry = carries[i];
    if (carry == 0) {
      continue;
    }
    for (int j = chunks[i].start; j < chunks[i].end; j++) {
      int64_t tmp;
      if (add_overflow_i64(dst[j], carry, &tmp)) {
        overflow = 1;
        break;
      }
      dst[j] = tmp;
    }
  }
  free(carries);
  free(summaries);
  free(chunks);
  if (overflow) {
    return LUNA_THREAD_STATUS_OVERFLOW;
  }
  return LUNA_THREAD_STATUS_OK;
}

const char *luna_thread_runtime_name(void) {
  return "luna_thread_runtime";
}

int luna_thread_runtime_has_openmp(void) {
#if defined(LUNA_THREAD_HAVE_OPENMP) || defined(_OPENMP)
  return 1;
#else
  return 0;
#endif
}

luna_thread_status luna_thread_map_i32(const luna_thread_map_request *req) {
  luna_thread_status status = validate_map(req);
  if (status != LUNA_THREAD_STATUS_OK) {
    return status;
  }
  return map_i32(req);
}

luna_thread_status luna_thread_map_i64(const luna_thread_map_request *req) {
  luna_thread_status status = validate_map(req);
  if (status != LUNA_THREAD_STATUS_OK) {
    return status;
  }
  return map_i64(req);
}

luna_thread_status luna_thread_reduce_sum_i32(const luna_thread_reduce_request *req) {
  luna_thread_status status = validate_reduce(req);
  if (status != LUNA_THREAD_STATUS_OK) {
    return status;
  }
  if (req->reduction_kernel != LUNA_THREAD_REDUCTION_SUM) {
    return LUNA_THREAD_STATUS_UNSUPPORTED_REDUCTION_KERNEL;
  }
  return reduce_sum_i32(req);
}

luna_thread_status luna_thread_reduce_sum_i64(const luna_thread_reduce_request *req) {
  luna_thread_status status = validate_reduce(req);
  if (status != LUNA_THREAD_STATUS_OK) {
    return status;
  }
  if (req->reduction_kernel != LUNA_THREAD_REDUCTION_SUM) {
    return LUNA_THREAD_STATUS_UNSUPPORTED_REDUCTION_KERNEL;
  }
  return reduce_sum_i64(req);
}

luna_thread_status luna_thread_reduce_min_i32(const luna_thread_reduce_request *req) {
  luna_thread_status status = validate_reduce(req);
  if (status != LUNA_THREAD_STATUS_OK) {
    return status;
  }
  if (req->reduction_kernel != LUNA_THREAD_REDUCTION_MIN) {
    return LUNA_THREAD_STATUS_UNSUPPORTED_REDUCTION_KERNEL;
  }
  return reduce_min_i32(req);
}

luna_thread_status luna_thread_reduce_min_i64(const luna_thread_reduce_request *req) {
  luna_thread_status status = validate_reduce(req);
  if (status != LUNA_THREAD_STATUS_OK) {
    return status;
  }
  if (req->reduction_kernel != LUNA_THREAD_REDUCTION_MIN) {
    return LUNA_THREAD_STATUS_UNSUPPORTED_REDUCTION_KERNEL;
  }
  return reduce_min_i64(req);
}

luna_thread_status luna_thread_reduce_max_i32(const luna_thread_reduce_request *req) {
  luna_thread_status status = validate_reduce(req);
  if (status != LUNA_THREAD_STATUS_OK) {
    return status;
  }
  if (req->reduction_kernel != LUNA_THREAD_REDUCTION_MAX) {
    return LUNA_THREAD_STATUS_UNSUPPORTED_REDUCTION_KERNEL;
  }
  return reduce_max_i32(req);
}

luna_thread_status luna_thread_reduce_max_i64(const luna_thread_reduce_request *req) {
  luna_thread_status status = validate_reduce(req);
  if (status != LUNA_THREAD_STATUS_OK) {
    return status;
  }
  if (req->reduction_kernel != LUNA_THREAD_REDUCTION_MAX) {
    return LUNA_THREAD_STATUS_UNSUPPORTED_REDUCTION_KERNEL;
  }
  return reduce_max_i64(req);
}

luna_thread_status luna_thread_scan_i32(const luna_thread_scan_request *req) {
  luna_thread_status status = validate_scan(req);
  if (status != LUNA_THREAD_STATUS_OK) {
    return status;
  }
  return scan_sum_i32(req);
}

luna_thread_status luna_thread_scan_i64(const luna_thread_scan_request *req) {
  luna_thread_status status = validate_scan(req);
  if (status != LUNA_THREAD_STATUS_OK) {
    return status;
  }
  return scan_sum_i64(req);
}

luna_thread_status luna_thread_workflow_submit(const luna_thread_workflow_request *req) {
  luna_thread_workflow_handle *handle = NULL;
  luna_thread_status status = luna_thread_workflow_submit_async(req, &handle);
  if (status != LUNA_THREAD_STATUS_OK) {
    return status;
  }
  luna_thread_workflow_result result;
  luna_thread_workflow_wait(handle, &result);
  luna_thread_workflow_destroy(handle);
  return result.status;
}

luna_thread_status luna_thread_workflow_submit_async(
  const luna_thread_workflow_request *req,
  luna_thread_workflow_handle **out_handle
) {
  if (out_handle == NULL) {
    return LUNA_THREAD_STATUS_NULL_POINTER;
  }
  *out_handle = NULL;
  luna_thread_status status = validate_workflow(req);
  if (status != LUNA_THREAD_STATUS_OK) {
    return status;
  }
  luna_thread_workflow_handle *handle = malloc(sizeof(luna_thread_workflow_handle));
  if (handle == NULL) {
    return LUNA_THREAD_STATUS_INVALID_ARGUMENT;
  }
  status = workflow_runtime_start(handle, req);
  if (status != LUNA_THREAD_STATUS_OK) {
    free(handle);
    return status;
  }
  *out_handle = handle;
  return LUNA_THREAD_STATUS_OK;
}

luna_thread_status luna_thread_workflow_poll(
  luna_thread_workflow_handle *handle,
  luna_thread_workflow_result *out_result
) {
  if (handle == NULL || out_result == NULL) {
    return LUNA_THREAD_STATUS_NULL_POINTER;
  }
  pthread_mutex_lock(&handle->runtime.mutex);
  out_result->state = handle->runtime.state;
  out_result->status = handle->runtime.status;
  out_result->completed_nodes = handle->runtime.completed_nodes;
  out_result->failed_node_id = handle->runtime.failed_node_id;
  pthread_mutex_unlock(&handle->runtime.mutex);
  return LUNA_THREAD_STATUS_OK;
}

luna_thread_status luna_thread_workflow_wait(
  luna_thread_workflow_handle *handle,
  luna_thread_workflow_result *out_result
) {
  if (handle == NULL || out_result == NULL) {
    return LUNA_THREAD_STATUS_NULL_POINTER;
  }
  pthread_mutex_lock(&handle->runtime.mutex);
  while (handle->runtime.state != LUNA_THREAD_WORKFLOW_STATE_COMPLETED &&
         handle->runtime.state != LUNA_THREAD_WORKFLOW_STATE_FAILED &&
         handle->runtime.state != LUNA_THREAD_WORKFLOW_STATE_REJECTED) {
    pthread_cond_wait(&handle->runtime.cond, &handle->runtime.mutex);
  }
  out_result->state = handle->runtime.state;
  out_result->status = handle->runtime.status;
  out_result->completed_nodes = handle->runtime.completed_nodes;
  out_result->failed_node_id = handle->runtime.failed_node_id;
  luna_thread_status status = handle->runtime.status;
  pthread_mutex_unlock(&handle->runtime.mutex);
  return status;
}

void luna_thread_workflow_destroy(luna_thread_workflow_handle *handle) {
  if (handle == NULL) {
    return;
  }
  workflow_runtime_stop(handle);
  free(handle);
}
