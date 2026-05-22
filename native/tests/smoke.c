#include "luna_thread_runtime.h"

#include <limits.h>
#include <stdio.h>

int main(void) {
  int32_t input[] = {1, 2, 3, 4};
  int32_t mapped[] = {0, 0, 0, 0};
  int32_t reduced = 0;
  int32_t scanned[] = {0, 0, 0, 0};

  luna_thread_map_request map_req = {
    .input = { .ptr = input, .length = 4 },
    .output = { .ptr = mapped, .length = 4 },
    .element_count = 4,
    .value_type = LUNA_THREAD_VALUE_I32,
    .worker_count = 2,
    .chunk_size = 2,
  };

  luna_thread_reduce_request reduce_req = {
    .input = { .ptr = input, .length = 4 },
    .output = { .ptr = &reduced, .length = 1 },
    .element_count = 4,
    .value_type = LUNA_THREAD_VALUE_I32,
    .reduction_kernel = LUNA_THREAD_REDUCTION_SUM,
    .worker_count = 2,
    .chunk_size = 2,
  };

  luna_thread_scan_request scan_req = {
    .input = { .ptr = input, .length = 4 },
    .output = { .ptr = scanned, .length = 4 },
    .element_count = 4,
    .value_type = LUNA_THREAD_VALUE_I32,
    .reduction_kernel = LUNA_THREAD_REDUCTION_SUM,
    .worker_count = 2,
    .chunk_size = 2,
  };

  if (luna_thread_map_i32(&map_req) != LUNA_THREAD_STATUS_OK) {
    return 1;
  }
  if (luna_thread_reduce_sum_i32(&reduce_req) != LUNA_THREAD_STATUS_OK) {
    return 1;
  }
  if (luna_thread_scan_i32(&scan_req) != LUNA_THREAD_STATUS_OK) {
    return 1;
  }
  if (mapped[0] != 2 || reduced != 10 || scanned[0] != 1 || scanned[1] != 3 ||
      scanned[2] != 6 || scanned[3] != 10) {
    return 1;
  }

  {
    int32_t overflow_in[] = {INT32_MAX};
    int32_t overflow_out[] = {0};
    luna_thread_map_request overflow_req = {
      .input = { .ptr = overflow_in, .length = 1 },
      .output = { .ptr = overflow_out, .length = 1 },
      .element_count = 1,
      .value_type = LUNA_THREAD_VALUE_I32,
      .worker_count = 1,
      .chunk_size = 1,
    };
    if (luna_thread_map_i32(&overflow_req) != LUNA_THREAD_STATUS_OVERFLOW) {
      return 2;
    }
  }

  {
    int32_t bad_sum_in[] = {1, 2};
    int32_t bad_sum_out = 0;
    luna_thread_reduce_request bad_reduce_req = {
      .input = { .ptr = bad_sum_in, .length = 2 },
      .output = { .ptr = &bad_sum_out, .length = 1 },
      .element_count = 2,
      .value_type = LUNA_THREAD_VALUE_I32,
      .reduction_kernel = LUNA_THREAD_REDUCTION_SUM,
      .worker_count = 3,
      .chunk_size = 1,
    };
    if (luna_thread_reduce_sum_i32(&bad_reduce_req) != LUNA_THREAD_STATUS_INVALID_ARGUMENT) {
      return 3;
    }
  }

  {
    int32_t unsupported_scan_out[] = {0, 0, 0, 0};
    luna_thread_scan_request bad_scan_req = {
      .input = { .ptr = input, .length = 4 },
      .output = { .ptr = unsupported_scan_out, .length = 4 },
      .element_count = 4,
      .value_type = LUNA_THREAD_VALUE_I32,
      .reduction_kernel = LUNA_THREAD_REDUCTION_MIN,
      .worker_count = 2,
      .chunk_size = 2,
    };
    if (luna_thread_scan_i32(&bad_scan_req) != LUNA_THREAD_STATUS_UNSUPPORTED_REDUCTION_KERNEL) {
      return 4;
    }
  }

  {
    luna_thread_workflow_capability capabilities[] = {
      { .id = 1, .kind = LUNA_THREAD_CAP_CHANNEL },
      { .id = 2, .kind = LUNA_THREAD_CAP_MUTEX },
      { .id = 3, .kind = LUNA_THREAD_CAP_CONDVAR },
      { .id = 4, .kind = LUNA_THREAD_CAP_BARRIER },
    };
    luna_thread_workflow_node nodes[] = {
      { .id = 1, .kind = LUNA_THREAD_WORKFLOW_NODE_SPAWN, .capability_id = -1 },
      { .id = 2, .kind = LUNA_THREAD_WORKFLOW_NODE_SEND, .capability_id = 1 },
      { .id = 3, .kind = LUNA_THREAD_WORKFLOW_NODE_LOCK, .capability_id = 2 },
      { .id = 4, .kind = LUNA_THREAD_WORKFLOW_NODE_SIGNAL, .capability_id = 3 },
      { .id = 5, .kind = LUNA_THREAD_WORKFLOW_NODE_BARRIER, .capability_id = 4 },
      { .id = 6, .kind = LUNA_THREAD_WORKFLOW_NODE_JOIN, .capability_id = -1 },
    };
    luna_thread_workflow_edge edges[] = {
      { .from = 1, .to = 2, .kind = LUNA_THREAD_WORKFLOW_EDGE_CONTROL },
      { .from = 2, .to = 3, .kind = LUNA_THREAD_WORKFLOW_EDGE_CONTROL },
      { .from = 3, .to = 4, .kind = LUNA_THREAD_WORKFLOW_EDGE_SYNC },
      { .from = 4, .to = 5, .kind = LUNA_THREAD_WORKFLOW_EDGE_SYNC },
      { .from = 5, .to = 6, .kind = LUNA_THREAD_WORKFLOW_EDGE_CONTROL },
    };
    luna_thread_workflow_request workflow_req = {
      .worker_count = 2,
      .capability_count = 4,
      .node_count = 6,
      .edge_count = 5,
      .capabilities = capabilities,
      .nodes = nodes,
      .edges = edges,
    };
    if (luna_thread_workflow_submit(&workflow_req) != LUNA_THREAD_STATUS_BARRIER_BROKEN) {
      return 5;
    }
  }

  {
    luna_thread_workflow_capability capabilities[] = {
      { .id = 1, .kind = LUNA_THREAD_CAP_CHANNEL },
      { .id = 2, .kind = LUNA_THREAD_CAP_MUTEX },
      { .id = 3, .kind = LUNA_THREAD_CAP_CONDVAR },
      { .id = 4, .kind = LUNA_THREAD_CAP_BARRIER },
    };
    luna_thread_workflow_node nodes[] = {
      { .id = 1, .kind = LUNA_THREAD_WORKFLOW_NODE_SPAWN, .capability_id = -1 },
      { .id = 2, .kind = LUNA_THREAD_WORKFLOW_NODE_SEND, .capability_id = 1 },
      { .id = 3, .kind = LUNA_THREAD_WORKFLOW_NODE_LOCK, .capability_id = 2 },
      { .id = 4, .kind = LUNA_THREAD_WORKFLOW_NODE_WAIT, .capability_id = 3 },
      { .id = 5, .kind = LUNA_THREAD_WORKFLOW_NODE_SIGNAL, .capability_id = 3 },
      { .id = 6, .kind = LUNA_THREAD_WORKFLOW_NODE_BARRIER, .capability_id = 4 },
      { .id = 7, .kind = LUNA_THREAD_WORKFLOW_NODE_BARRIER, .capability_id = 4 },
      { .id = 8, .kind = LUNA_THREAD_WORKFLOW_NODE_JOIN, .capability_id = -1 },
    };
    luna_thread_workflow_edge edges[] = {
      { .from = 1, .to = 2, .kind = LUNA_THREAD_WORKFLOW_EDGE_CONTROL },
      { .from = 2, .to = 3, .kind = LUNA_THREAD_WORKFLOW_EDGE_CONTROL },
      { .from = 3, .to = 4, .kind = LUNA_THREAD_WORKFLOW_EDGE_SYNC },
      { .from = 3, .to = 5, .kind = LUNA_THREAD_WORKFLOW_EDGE_SYNC },
      { .from = 4, .to = 6, .kind = LUNA_THREAD_WORKFLOW_EDGE_SYNC },
      { .from = 5, .to = 7, .kind = LUNA_THREAD_WORKFLOW_EDGE_SYNC },
      { .from = 6, .to = 8, .kind = LUNA_THREAD_WORKFLOW_EDGE_CONTROL },
      { .from = 7, .to = 8, .kind = LUNA_THREAD_WORKFLOW_EDGE_CONTROL },
    };
    luna_thread_workflow_request workflow_req = {
      .worker_count = 2,
      .capability_count = 4,
      .node_count = 8,
      .edge_count = 8,
      .capabilities = capabilities,
      .nodes = nodes,
      .edges = edges,
    };
    luna_thread_workflow_handle *handle = NULL;
    luna_thread_workflow_result result = {0};
    if (luna_thread_workflow_submit_async(&workflow_req, &handle) != LUNA_THREAD_STATUS_OK) {
      return 6;
    }
    if (luna_thread_workflow_poll(handle, &result) != LUNA_THREAD_STATUS_OK) {
      return 7;
    }
    if (luna_thread_workflow_wait(handle, &result) != LUNA_THREAD_STATUS_OK) {
      return 8;
    }
    if (result.state != LUNA_THREAD_WORKFLOW_STATE_COMPLETED || result.completed_nodes != 8) {
      return 9;
    }
    luna_thread_workflow_destroy(handle);
  }

  {
    luna_thread_workflow_capability capabilities[] = {
      { .id = 1, .kind = LUNA_THREAD_CAP_CHANNEL },
    };
    luna_thread_workflow_node nodes[] = {
      { .id = 1, .kind = LUNA_THREAD_WORKFLOW_NODE_LOCK, .capability_id = 1 },
    };
    luna_thread_workflow_request bad_workflow_req = {
      .worker_count = 1,
      .capability_count = 1,
      .node_count = 1,
      .edge_count = 0,
      .capabilities = capabilities,
      .nodes = nodes,
      .edges = NULL,
    };
    if (luna_thread_workflow_submit(&bad_workflow_req) != LUNA_THREAD_STATUS_INVALID_ARGUMENT) {
      return 10;
    }
  }

  printf("%s %d %d %d\n", luna_thread_runtime_name(), mapped[0], reduced, scanned[3]);
  return 0;
}
