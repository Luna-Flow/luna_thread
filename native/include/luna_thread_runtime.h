#ifndef LUNA_THREAD_RUNTIME_H
#define LUNA_THREAD_RUNTIME_H

#ifdef __cplusplus
extern "C" {
#endif

const char *luna_thread_runtime_name(void);
int luna_thread_runtime_has_openmp(void);

#ifdef __cplusplus
}
#endif

#endif
