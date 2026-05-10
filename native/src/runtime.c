#include "luna_thread_runtime.h"

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
