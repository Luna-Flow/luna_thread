#include "luna_thread_runtime.h"

#include <limits.h>
#include <stdlib.h>
#include <stddef.h>
#include <stdint.h>

#if defined(LUNA_THREAD_HAVE_OPENMP) || defined(_OPENMP)
#include <omp.h>
#endif

typedef struct {
  int start;
  int end;
} luna_thread_chunk;

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
