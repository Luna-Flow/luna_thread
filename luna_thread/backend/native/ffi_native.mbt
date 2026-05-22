///|
#external
pub type NativeWorkflowHandle

///|
#cfg(target="native")
#borrow(input, output)
pub extern "C" fn ffi_execute_map_i32(
  input : FixedArray[Int],
  length : Int,
  worker_count : Int,
  chunk_size : Int,
  output : FixedArray[Int],
) -> Int = "luna_mbt_execute_map_i32"

///|
#cfg(target="native")
#borrow(input, output)
pub extern "C" fn ffi_execute_map_i64(
  input : FixedArray[Int64],
  length : Int,
  worker_count : Int,
  chunk_size : Int,
  output : FixedArray[Int64],
) -> Int = "luna_mbt_execute_map_i64"

///|
#cfg(target="native")
#borrow(input)
pub extern "C" fn ffi_execute_reduce_sum_i32(
  input : FixedArray[Int],
  length : Int,
  worker_count : Int,
  chunk_size : Int,
) -> Int = "luna_mbt_execute_reduce_sum_i32"

///|
#cfg(target="native")
#borrow(input)
pub extern "C" fn ffi_execute_reduce_sum_i64(
  input : FixedArray[Int64],
  length : Int,
  worker_count : Int,
  chunk_size : Int,
) -> Int64 = "luna_mbt_execute_reduce_sum_i64"

///|
#cfg(target="native")
#borrow(input)
pub extern "C" fn ffi_execute_reduce_min_i32(
  input : FixedArray[Int],
  length : Int,
  worker_count : Int,
  chunk_size : Int,
) -> Int = "luna_mbt_execute_reduce_min_i32"

///|
#cfg(target="native")
#borrow(input)
pub extern "C" fn ffi_execute_reduce_min_i64(
  input : FixedArray[Int64],
  length : Int,
  worker_count : Int,
  chunk_size : Int,
) -> Int64 = "luna_mbt_execute_reduce_min_i64"

///|
#cfg(target="native")
#borrow(input)
pub extern "C" fn ffi_execute_reduce_max_i32(
  input : FixedArray[Int],
  length : Int,
  worker_count : Int,
  chunk_size : Int,
) -> Int = "luna_mbt_execute_reduce_max_i32"

///|
#cfg(target="native")
#borrow(input)
pub extern "C" fn ffi_execute_reduce_max_i64(
  input : FixedArray[Int64],
  length : Int,
  worker_count : Int,
  chunk_size : Int,
) -> Int64 = "luna_mbt_execute_reduce_max_i64"

///|
#cfg(target="native")
#borrow(input, output)
pub extern "C" fn ffi_execute_scan_sum_i32(
  input : FixedArray[Int],
  length : Int,
  worker_count : Int,
  chunk_size : Int,
  output : FixedArray[Int],
) -> Int = "luna_mbt_execute_scan_sum_i32"

///|
#cfg(target="native")
#borrow(input, output)
pub extern "C" fn ffi_execute_scan_sum_i64(
  input : FixedArray[Int64],
  length : Int,
  worker_count : Int,
  chunk_size : Int,
  output : FixedArray[Int64],
) -> Int = "luna_mbt_execute_scan_sum_i64"

///|
#cfg(target="native")
#borrow(capability_ids, capability_kinds, node_ids, node_kinds, node_capability_ids, edge_froms, edge_tos, edge_kinds)
pub extern "C" fn ffi_submit_workflow_async(
  worker_count : Int,
  capability_ids : FixedArray[Int],
  capability_kinds : FixedArray[Int],
  capability_count : Int,
  node_ids : FixedArray[Int],
  node_kinds : FixedArray[Int],
  node_capability_ids : FixedArray[Int],
  node_count : Int,
  edge_froms : FixedArray[Int],
  edge_tos : FixedArray[Int],
  edge_kinds : FixedArray[Int],
  edge_count : Int,
) -> NativeWorkflowHandle = "luna_mbt_workflow_submit_async"

///|
#cfg(target="native")
pub extern "C" fn ffi_workflow_poll_state(
  handle : NativeWorkflowHandle,
) -> Int = "luna_mbt_workflow_poll_state"

///|
#cfg(target="native")
pub extern "C" fn ffi_workflow_poll_status(
  handle : NativeWorkflowHandle,
) -> Int = "luna_mbt_workflow_poll_status"

///|
#cfg(target="native")
pub extern "C" fn ffi_workflow_poll_completed_nodes(
  handle : NativeWorkflowHandle,
) -> Int = "luna_mbt_workflow_poll_completed_nodes"

///|
#cfg(target="native")
pub extern "C" fn ffi_workflow_poll_failed_node_id(
  handle : NativeWorkflowHandle,
) -> Int = "luna_mbt_workflow_poll_failed_node_id"

///|
#cfg(target="native")
pub extern "C" fn ffi_workflow_wait_status(
  handle : NativeWorkflowHandle,
) -> Int = "luna_mbt_workflow_wait_status"

///|
#cfg(target="native")
pub extern "C" fn ffi_workflow_destroy(
  handle : NativeWorkflowHandle,
) -> Unit = "luna_mbt_workflow_destroy"
