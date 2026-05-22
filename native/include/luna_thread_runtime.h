#ifndef LUNA_THREAD_RUNTIME_H
#define LUNA_THREAD_RUNTIME_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef enum {
  LUNA_THREAD_STATUS_OK = 0,
  LUNA_THREAD_STATUS_INVALID_ARGUMENT = 1,
  LUNA_THREAD_STATUS_UNSUPPORTED_BACKEND = 2,
  LUNA_THREAD_STATUS_UNSUPPORTED_MODE = 3,
  LUNA_THREAD_STATUS_UNSUPPORTED_VALUE_TYPE = 4,
  LUNA_THREAD_STATUS_UNSUPPORTED_REDUCTION_KERNEL = 5,
  LUNA_THREAD_STATUS_OVERFLOW = 6,
  LUNA_THREAD_STATUS_NULL_POINTER = 7,
  LUNA_THREAD_STATUS_UNSUPPORTED_RUNTIME_PRIMITIVE = 8,
  LUNA_THREAD_STATUS_RUNTIME_BROKEN = 9,
  LUNA_THREAD_STATUS_CHANNEL_EMPTY = 10,
  LUNA_THREAD_STATUS_CHANNEL_CLOSED = 11,
  LUNA_THREAD_STATUS_MUTEX_PROTOCOL_ERROR = 12,
  LUNA_THREAD_STATUS_CONDVAR_PROTOCOL_ERROR = 13,
  LUNA_THREAD_STATUS_BARRIER_BROKEN = 14,
} luna_thread_status;

typedef enum {
  LUNA_THREAD_VALUE_I32 = 0,
  LUNA_THREAD_VALUE_I64 = 1,
} luna_thread_value_type;

typedef enum {
  LUNA_THREAD_REDUCTION_SUM = 0,
  LUNA_THREAD_REDUCTION_MIN = 1,
  LUNA_THREAD_REDUCTION_MAX = 2,
} luna_thread_reduction_kernel;

typedef struct {
  const void *ptr;
  int length;
} luna_thread_buffer;

typedef struct {
  luna_thread_buffer input;
  luna_thread_buffer output;
  int element_count;
  luna_thread_value_type value_type;
  int worker_count;
  int chunk_size;
} luna_thread_map_request;

typedef struct {
  luna_thread_buffer input;
  luna_thread_buffer output;
  int element_count;
  luna_thread_value_type value_type;
  luna_thread_reduction_kernel reduction_kernel;
  int worker_count;
  int chunk_size;
} luna_thread_reduce_request;

typedef struct {
  luna_thread_buffer input;
  luna_thread_buffer output;
  int element_count;
  luna_thread_value_type value_type;
  luna_thread_reduction_kernel reduction_kernel;
  int worker_count;
  int chunk_size;
} luna_thread_scan_request;

typedef enum {
  LUNA_THREAD_CAP_OWNED_BUFFER = 0,
  LUNA_THREAD_CAP_SHARED_READ_VIEW = 1,
  LUNA_THREAD_CAP_ATOMIC_CELL = 2,
  LUNA_THREAD_CAP_MUTEX = 3,
  LUNA_THREAD_CAP_CONDVAR = 4,
  LUNA_THREAD_CAP_RWLOCK = 5,
  LUNA_THREAD_CAP_SEMAPHORE = 6,
  LUNA_THREAD_CAP_BARRIER = 7,
  LUNA_THREAD_CAP_CHANNEL = 8,
  LUNA_THREAD_CAP_OPAQUE = 9,
} luna_thread_capability_kind;

typedef enum {
  LUNA_THREAD_WORKFLOW_NODE_COMPUTE = 0,
  LUNA_THREAD_WORKFLOW_NODE_SPAWN = 1,
  LUNA_THREAD_WORKFLOW_NODE_JOIN = 2,
  LUNA_THREAD_WORKFLOW_NODE_SEND = 3,
  LUNA_THREAD_WORKFLOW_NODE_RECV = 4,
  LUNA_THREAD_WORKFLOW_NODE_LOCK = 5,
  LUNA_THREAD_WORKFLOW_NODE_UNLOCK = 6,
  LUNA_THREAD_WORKFLOW_NODE_WAIT = 7,
  LUNA_THREAD_WORKFLOW_NODE_SIGNAL = 8,
  LUNA_THREAD_WORKFLOW_NODE_BARRIER = 9,
  LUNA_THREAD_WORKFLOW_NODE_READ_SHARED = 10,
  LUNA_THREAD_WORKFLOW_NODE_WRITE_SHARED = 11,
} luna_thread_workflow_node_kind;

typedef enum {
  LUNA_THREAD_WORKFLOW_EDGE_DATA = 0,
  LUNA_THREAD_WORKFLOW_EDGE_CONTROL = 1,
  LUNA_THREAD_WORKFLOW_EDGE_OWNERSHIP = 2,
  LUNA_THREAD_WORKFLOW_EDGE_SYNC = 3,
} luna_thread_workflow_edge_kind;

typedef struct {
  int id;
  luna_thread_capability_kind kind;
} luna_thread_workflow_capability;

typedef struct {
  int id;
  luna_thread_workflow_node_kind kind;
  int capability_id;
} luna_thread_workflow_node;

typedef struct {
  int from;
  int to;
  luna_thread_workflow_edge_kind kind;
} luna_thread_workflow_edge;

typedef struct {
  int worker_count;
  int capability_count;
  int node_count;
  int edge_count;
  const luna_thread_workflow_capability *capabilities;
  const luna_thread_workflow_node *nodes;
  const luna_thread_workflow_edge *edges;
} luna_thread_workflow_request;

typedef struct luna_thread_workflow_handle luna_thread_workflow_handle;

typedef enum {
  LUNA_THREAD_WORKFLOW_STATE_SUBMITTED = 0,
  LUNA_THREAD_WORKFLOW_STATE_RUNNING = 1,
  LUNA_THREAD_WORKFLOW_STATE_COMPLETED = 2,
  LUNA_THREAD_WORKFLOW_STATE_FAILED = 3,
  LUNA_THREAD_WORKFLOW_STATE_REJECTED = 4,
} luna_thread_workflow_state;

typedef struct {
  luna_thread_workflow_state state;
  luna_thread_status status;
  int completed_nodes;
  int failed_node_id;
} luna_thread_workflow_result;

const char *luna_thread_runtime_name(void);
int luna_thread_runtime_has_openmp(void);

luna_thread_status luna_thread_map_i32(const luna_thread_map_request *req);
luna_thread_status luna_thread_map_i64(const luna_thread_map_request *req);
luna_thread_status luna_thread_reduce_sum_i32(const luna_thread_reduce_request *req);
luna_thread_status luna_thread_reduce_sum_i64(const luna_thread_reduce_request *req);
luna_thread_status luna_thread_reduce_min_i32(const luna_thread_reduce_request *req);
luna_thread_status luna_thread_reduce_min_i64(const luna_thread_reduce_request *req);
luna_thread_status luna_thread_reduce_max_i32(const luna_thread_reduce_request *req);
luna_thread_status luna_thread_reduce_max_i64(const luna_thread_reduce_request *req);
luna_thread_status luna_thread_scan_i32(const luna_thread_scan_request *req);
luna_thread_status luna_thread_scan_i64(const luna_thread_scan_request *req);
luna_thread_status luna_thread_workflow_submit(const luna_thread_workflow_request *req);
luna_thread_status luna_thread_workflow_submit_async(
  const luna_thread_workflow_request *req,
  luna_thread_workflow_handle **out_handle
);
luna_thread_status luna_thread_workflow_poll(
  luna_thread_workflow_handle *handle,
  luna_thread_workflow_result *out_result
);
luna_thread_status luna_thread_workflow_wait(
  luna_thread_workflow_handle *handle,
  luna_thread_workflow_result *out_result
);
void luna_thread_workflow_destroy(luna_thread_workflow_handle *handle);

#ifdef __cplusplus
}
#endif

#endif
