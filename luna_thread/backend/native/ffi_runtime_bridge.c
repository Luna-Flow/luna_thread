#include "../../../native/include/luna_thread_runtime.h"

#include <stdint.h>
#include <stdlib.h>

static luna_thread_workflow_result luna_mbt_workflow_snapshot(
  luna_thread_workflow_handle *handle
) {
  luna_thread_workflow_result result = {0};
  luna_thread_workflow_poll(handle, &result);
  return result;
}

int32_t luna_mbt_execute_map_i32(
  const int32_t *input,
  int32_t length,
  int32_t worker_count,
  int32_t chunk_size,
  int32_t *output
) {
  luna_thread_map_request req = {
    .input = { .ptr = input, .length = length },
    .output = { .ptr = output, .length = length },
    .element_count = length,
    .value_type = LUNA_THREAD_VALUE_I32,
    .worker_count = worker_count,
    .chunk_size = chunk_size,
  };
  return luna_thread_map_i32(&req);
}

int32_t luna_mbt_execute_map_i64(
  const int64_t *input,
  int32_t length,
  int32_t worker_count,
  int32_t chunk_size,
  int64_t *output
) {
  luna_thread_map_request req = {
    .input = { .ptr = input, .length = length },
    .output = { .ptr = output, .length = length },
    .element_count = length,
    .value_type = LUNA_THREAD_VALUE_I64,
    .worker_count = worker_count,
    .chunk_size = chunk_size,
  };
  return luna_thread_map_i64(&req);
}

int32_t luna_mbt_execute_reduce_sum_i32(
  const int32_t *input,
  int32_t length,
  int32_t worker_count,
  int32_t chunk_size
) {
  int32_t output = 0;
  luna_thread_reduce_request req = {
    .input = { .ptr = input, .length = length },
    .output = { .ptr = &output, .length = 1 },
    .element_count = length,
    .value_type = LUNA_THREAD_VALUE_I32,
    .reduction_kernel = LUNA_THREAD_REDUCTION_SUM,
    .worker_count = worker_count,
    .chunk_size = chunk_size,
  };
  if (luna_thread_reduce_sum_i32(&req) != LUNA_THREAD_STATUS_OK) {
    return 0;
  }
  return output;
}

int64_t luna_mbt_execute_reduce_sum_i64(
  const int64_t *input,
  int32_t length,
  int32_t worker_count,
  int32_t chunk_size
) {
  int64_t output = 0;
  luna_thread_reduce_request req = {
    .input = { .ptr = input, .length = length },
    .output = { .ptr = &output, .length = 1 },
    .element_count = length,
    .value_type = LUNA_THREAD_VALUE_I64,
    .reduction_kernel = LUNA_THREAD_REDUCTION_SUM,
    .worker_count = worker_count,
    .chunk_size = chunk_size,
  };
  if (luna_thread_reduce_sum_i64(&req) != LUNA_THREAD_STATUS_OK) {
    return 0;
  }
  return output;
}

int32_t luna_mbt_execute_reduce_min_i32(
  const int32_t *input,
  int32_t length,
  int32_t worker_count,
  int32_t chunk_size
) {
  int32_t output = 0;
  luna_thread_reduce_request req = {
    .input = { .ptr = input, .length = length },
    .output = { .ptr = &output, .length = 1 },
    .element_count = length,
    .value_type = LUNA_THREAD_VALUE_I32,
    .reduction_kernel = LUNA_THREAD_REDUCTION_MIN,
    .worker_count = worker_count,
    .chunk_size = chunk_size,
  };
  if (luna_thread_reduce_min_i32(&req) != LUNA_THREAD_STATUS_OK) {
    return 0;
  }
  return output;
}

int64_t luna_mbt_execute_reduce_min_i64(
  const int64_t *input,
  int32_t length,
  int32_t worker_count,
  int32_t chunk_size
) {
  int64_t output = 0;
  luna_thread_reduce_request req = {
    .input = { .ptr = input, .length = length },
    .output = { .ptr = &output, .length = 1 },
    .element_count = length,
    .value_type = LUNA_THREAD_VALUE_I64,
    .reduction_kernel = LUNA_THREAD_REDUCTION_MIN,
    .worker_count = worker_count,
    .chunk_size = chunk_size,
  };
  if (luna_thread_reduce_min_i64(&req) != LUNA_THREAD_STATUS_OK) {
    return 0;
  }
  return output;
}

int32_t luna_mbt_execute_reduce_max_i32(
  const int32_t *input,
  int32_t length,
  int32_t worker_count,
  int32_t chunk_size
) {
  int32_t output = 0;
  luna_thread_reduce_request req = {
    .input = { .ptr = input, .length = length },
    .output = { .ptr = &output, .length = 1 },
    .element_count = length,
    .value_type = LUNA_THREAD_VALUE_I32,
    .reduction_kernel = LUNA_THREAD_REDUCTION_MAX,
    .worker_count = worker_count,
    .chunk_size = chunk_size,
  };
  if (luna_thread_reduce_max_i32(&req) != LUNA_THREAD_STATUS_OK) {
    return 0;
  }
  return output;
}

int64_t luna_mbt_execute_reduce_max_i64(
  const int64_t *input,
  int32_t length,
  int32_t worker_count,
  int32_t chunk_size
) {
  int64_t output = 0;
  luna_thread_reduce_request req = {
    .input = { .ptr = input, .length = length },
    .output = { .ptr = &output, .length = 1 },
    .element_count = length,
    .value_type = LUNA_THREAD_VALUE_I64,
    .reduction_kernel = LUNA_THREAD_REDUCTION_MAX,
    .worker_count = worker_count,
    .chunk_size = chunk_size,
  };
  if (luna_thread_reduce_max_i64(&req) != LUNA_THREAD_STATUS_OK) {
    return 0;
  }
  return output;
}

int32_t luna_mbt_execute_scan_sum_i32(
  const int32_t *input,
  int32_t length,
  int32_t worker_count,
  int32_t chunk_size,
  int32_t *output
) {
  luna_thread_scan_request req = {
    .input = { .ptr = input, .length = length },
    .output = { .ptr = output, .length = length },
    .element_count = length,
    .value_type = LUNA_THREAD_VALUE_I32,
    .reduction_kernel = LUNA_THREAD_REDUCTION_SUM,
    .worker_count = worker_count,
    .chunk_size = chunk_size,
  };
  return luna_thread_scan_i32(&req);
}

int32_t luna_mbt_execute_scan_sum_i64(
  const int64_t *input,
  int32_t length,
  int32_t worker_count,
  int32_t chunk_size,
  int64_t *output
) {
  luna_thread_scan_request req = {
    .input = { .ptr = input, .length = length },
    .output = { .ptr = output, .length = length },
    .element_count = length,
    .value_type = LUNA_THREAD_VALUE_I64,
    .reduction_kernel = LUNA_THREAD_REDUCTION_SUM,
    .worker_count = worker_count,
    .chunk_size = chunk_size,
  };
  return luna_thread_scan_i64(&req);
}

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
) {
  luna_thread_workflow_capability *caps = NULL;
  luna_thread_workflow_node *nodes = NULL;
  luna_thread_workflow_edge *edges = NULL;
  luna_thread_workflow_handle *handle = NULL;
  if (capability_count > 0) {
    caps = malloc(sizeof(luna_thread_workflow_capability) * (size_t)capability_count);
  }
  if (node_count > 0) {
    nodes = malloc(sizeof(luna_thread_workflow_node) * (size_t)node_count);
  }
  if (edge_count > 0) {
    edges = malloc(sizeof(luna_thread_workflow_edge) * (size_t)edge_count);
  }
  for (int i = 0; i < capability_count; i++) {
    caps[i].id = capability_ids[i];
    caps[i].kind = (luna_thread_capability_kind)capability_kinds[i];
  }
  for (int i = 0; i < node_count; i++) {
    nodes[i].id = node_ids[i];
    nodes[i].kind = (luna_thread_workflow_node_kind)node_kinds[i];
    nodes[i].capability_id = node_capability_ids[i];
  }
  for (int i = 0; i < edge_count; i++) {
    edges[i].from = edge_froms[i];
    edges[i].to = edge_tos[i];
    edges[i].kind = (luna_thread_workflow_edge_kind)edge_kinds[i];
  }
  luna_thread_workflow_request req = {
    .worker_count = worker_count,
    .capability_count = capability_count,
    .node_count = node_count,
    .edge_count = edge_count,
    .capabilities = caps,
    .nodes = nodes,
    .edges = edges,
  };
  if (luna_thread_workflow_submit_async(&req, &handle) != LUNA_THREAD_STATUS_OK) {
    free(caps);
    free(nodes);
    free(edges);
    return NULL;
  }
  free(caps);
  free(nodes);
  free(edges);
  return handle;
}

int32_t luna_mbt_workflow_poll_state(void *handle) {
  luna_thread_workflow_result result = luna_mbt_workflow_snapshot((luna_thread_workflow_handle *)handle);
  return result.state;
}

int32_t luna_mbt_workflow_poll_status(void *handle) {
  luna_thread_workflow_result result = luna_mbt_workflow_snapshot((luna_thread_workflow_handle *)handle);
  return result.status;
}

int32_t luna_mbt_workflow_poll_completed_nodes(void *handle) {
  luna_thread_workflow_result result = luna_mbt_workflow_snapshot((luna_thread_workflow_handle *)handle);
  return result.completed_nodes;
}

int32_t luna_mbt_workflow_poll_failed_node_id(void *handle) {
  luna_thread_workflow_result result = luna_mbt_workflow_snapshot((luna_thread_workflow_handle *)handle);
  return result.failed_node_id;
}

int32_t luna_mbt_workflow_wait_status(void *handle) {
  luna_thread_workflow_result result = {0};
  return luna_thread_workflow_wait((luna_thread_workflow_handle *)handle, &result);
}

void luna_mbt_workflow_destroy(void *handle) {
  luna_thread_workflow_destroy((luna_thread_workflow_handle *)handle);
}
