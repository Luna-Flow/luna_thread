#include "../../../native/include/luna_thread_runtime.h"

#include <stdint.h>

int32_t luna_mbt_execute_map_i32(
  const int32_t *input,
  int32_t length,
  int32_t worker_count,
  int32_t chunk_size,
  int32_t *output
);

int32_t luna_mbt_execute_map_i64(
  const int64_t *input,
  int32_t length,
  int32_t worker_count,
  int32_t chunk_size,
  int64_t *output
);

int32_t luna_mbt_execute_reduce_sum_i32(
  const int32_t *input,
  int32_t length,
  int32_t worker_count,
  int32_t chunk_size
);

int64_t luna_mbt_execute_reduce_sum_i64(
  const int64_t *input,
  int32_t length,
  int32_t worker_count,
  int32_t chunk_size
);

int32_t luna_mbt_execute_reduce_min_i32(
  const int32_t *input,
  int32_t length,
  int32_t worker_count,
  int32_t chunk_size
);

int64_t luna_mbt_execute_reduce_min_i64(
  const int64_t *input,
  int32_t length,
  int32_t worker_count,
  int32_t chunk_size
);

int32_t luna_mbt_execute_reduce_max_i32(
  const int32_t *input,
  int32_t length,
  int32_t worker_count,
  int32_t chunk_size
);

int64_t luna_mbt_execute_reduce_max_i64(
  const int64_t *input,
  int32_t length,
  int32_t worker_count,
  int32_t chunk_size
);

int32_t luna_mbt_execute_scan_sum_i32(
  const int32_t *input,
  int32_t length,
  int32_t worker_count,
  int32_t chunk_size,
  int32_t *output
);

int32_t luna_mbt_execute_scan_sum_i64(
  const int64_t *input,
  int32_t length,
  int32_t worker_count,
  int32_t chunk_size,
  int64_t *output
);

void *luna_mbt_workflow_submit_async(
  int32_t worker_count,
  const int32_t *capability_ids,
  const int32_t *capability_kinds,
  int32_t capability_count,
  const int32_t *node_ids,
  const int32_t *node_kinds,
  const int32_t *node_capability_ids,
  int32_t node_count,
  const int32_t *edge_froms,
  const int32_t *edge_tos,
  const int32_t *edge_kinds,
  int32_t edge_count
);

int32_t luna_mbt_workflow_poll_state(void *handle);
int32_t luna_mbt_workflow_poll_status(void *handle);
int32_t luna_mbt_workflow_poll_completed_nodes(void *handle);
int32_t luna_mbt_workflow_poll_failed_node_id(void *handle);
int32_t luna_mbt_workflow_wait_status(void *handle);
void luna_mbt_workflow_destroy(void *handle);
