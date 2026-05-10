#include "luna_thread_runtime.h"

#include <stdio.h>

int main(void) {
  printf("%s openmp=%d\n", luna_thread_runtime_name(), luna_thread_runtime_has_openmp());
  return 0;
}
