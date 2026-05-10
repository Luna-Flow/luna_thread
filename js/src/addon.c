#include <node_api.h>

static napi_value runtime_name(napi_env env, napi_callback_info info) {
  napi_value result;
  napi_create_string_utf8(env, "luna_thread_addon", NAPI_AUTO_LENGTH, &result);
  return result;
}

static napi_value init(napi_env env, napi_value exports) {
  napi_value fn;
  napi_create_function(env, "runtimeName", NAPI_AUTO_LENGTH, runtime_name, NULL, &fn);
  napi_set_named_property(env, exports, "runtimeName", fn);
  return exports;
}

NAPI_MODULE(NODE_GYP_MODULE_NAME, init)
