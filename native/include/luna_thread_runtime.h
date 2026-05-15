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

#ifdef __cplusplus
}
#endif

#endif
