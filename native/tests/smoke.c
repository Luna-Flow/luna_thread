#include "luna_thread_runtime.h"

#include <limits.h>
#include <stdio.h>

int main(void) {
  int32_t input[] = {1, 2, 3, 4};
  int32_t mapped[] = {0, 0, 0, 0};
  int32_t reduced = 0;

  luna_thread_map_request map_req = {
    .input = { .ptr = input, .length = 4 },
    .output = { .ptr = mapped, .length = 4 },
    .element_count = 4,
    .value_type = LUNA_THREAD_VALUE_I32,
    .worker_count = 1,
    .chunk_size = 1,
  };

  luna_thread_reduce_request reduce_req = {
    .input = { .ptr = input, .length = 4 },
    .output = { .ptr = &reduced, .length = 1 },
    .element_count = 4,
    .value_type = LUNA_THREAD_VALUE_I32,
    .reduction_kernel = LUNA_THREAD_REDUCTION_SUM,
    .worker_count = 1,
    .chunk_size = 1,
  };

  if (luna_thread_map_i32(&map_req) != LUNA_THREAD_STATUS_OK) {
    return 1;
  }
  if (luna_thread_reduce_sum_i32(&reduce_req) != LUNA_THREAD_STATUS_OK) {
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

  printf("%s %d %d\n", luna_thread_runtime_name(), mapped[0], reduced);
  return 0;
}
