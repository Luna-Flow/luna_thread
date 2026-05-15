#include "luna_thread_runtime.h"

#include <limits.h>
#include <stddef.h>
#include <stdint.h>

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
  return LUNA_THREAD_STATUS_OK;
}

static luna_thread_status map_i32(const luna_thread_map_request *req) {
  const int32_t *src = (const int32_t *)req->input.ptr;
  int32_t *dst = (int32_t *)req->output.ptr;
  int32_t tmp;
  for (int i = 0; i < req->element_count; i++) {
    if (add_overflow_i32(src[i], src[i], &tmp)) {
      return LUNA_THREAD_STATUS_OVERFLOW;
    }
  }
  for (int i = 0; i < req->element_count; i++) {
    dst[i] = src[i] + src[i];
  }
  return LUNA_THREAD_STATUS_OK;
}

static luna_thread_status map_i64(const luna_thread_map_request *req) {
  const int64_t *src = (const int64_t *)req->input.ptr;
  int64_t *dst = (int64_t *)req->output.ptr;
  int64_t tmp;
  for (int i = 0; i < req->element_count; i++) {
    if (add_overflow_i64(src[i], src[i], &tmp)) {
      return LUNA_THREAD_STATUS_OVERFLOW;
    }
  }
  for (int i = 0; i < req->element_count; i++) {
    dst[i] = src[i] + src[i];
  }
  return LUNA_THREAD_STATUS_OK;
}

static luna_thread_status reduce_sum_i32(const luna_thread_reduce_request *req) {
  const int32_t *src = (const int32_t *)req->input.ptr;
  int32_t acc = 0;
  int32_t tmp;
  for (int i = 0; i < req->element_count; i++) {
    if (add_overflow_i32(acc, src[i], &tmp)) {
      return LUNA_THREAD_STATUS_OVERFLOW;
    }
    acc = tmp;
  }
  *(int32_t *)req->output.ptr = acc;
  return LUNA_THREAD_STATUS_OK;
}

static luna_thread_status reduce_sum_i64(const luna_thread_reduce_request *req) {
  const int64_t *src = (const int64_t *)req->input.ptr;
  int64_t acc = 0;
  int64_t tmp;
  for (int i = 0; i < req->element_count; i++) {
    if (add_overflow_i64(acc, src[i], &tmp)) {
      return LUNA_THREAD_STATUS_OVERFLOW;
    }
    acc = tmp;
  }
  *(int64_t *)req->output.ptr = acc;
  return LUNA_THREAD_STATUS_OK;
}

static luna_thread_status reduce_min_i32(const luna_thread_reduce_request *req) {
  const int32_t *src = (const int32_t *)req->input.ptr;
  int32_t acc = src[0];
  for (int i = 1; i < req->element_count; i++) {
    if (src[i] < acc) {
      acc = src[i];
    }
  }
  *(int32_t *)req->output.ptr = acc;
  return LUNA_THREAD_STATUS_OK;
}

static luna_thread_status reduce_min_i64(const luna_thread_reduce_request *req) {
  const int64_t *src = (const int64_t *)req->input.ptr;
  int64_t acc = src[0];
  for (int i = 1; i < req->element_count; i++) {
    if (src[i] < acc) {
      acc = src[i];
    }
  }
  *(int64_t *)req->output.ptr = acc;
  return LUNA_THREAD_STATUS_OK;
}

static luna_thread_status reduce_max_i32(const luna_thread_reduce_request *req) {
  const int32_t *src = (const int32_t *)req->input.ptr;
  int32_t acc = src[0];
  for (int i = 1; i < req->element_count; i++) {
    if (src[i] > acc) {
      acc = src[i];
    }
  }
  *(int32_t *)req->output.ptr = acc;
  return LUNA_THREAD_STATUS_OK;
}

static luna_thread_status reduce_max_i64(const luna_thread_reduce_request *req) {
  const int64_t *src = (const int64_t *)req->input.ptr;
  int64_t acc = src[0];
  for (int i = 1; i < req->element_count; i++) {
    if (src[i] > acc) {
      acc = src[i];
    }
  }
  *(int64_t *)req->output.ptr = acc;
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
