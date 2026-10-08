///|
pub extend NativeValueType with Eq::{equal}

///|
#deprecated("Use `!=` instead", skip_current_package=true)
#doc(hidden)
pub extend NativeValueType with Eq::{not_equal}

///|
pub extend NativeReductionKernel with Eq::{equal}

///|
#deprecated("Use `!=` instead", skip_current_package=true)
#doc(hidden)
pub extend NativeReductionKernel with Eq::{not_equal}

///|
pub extend NativeRequestError with Eq::{equal}

///|
#deprecated("Use `!=` instead", skip_current_package=true)
#doc(hidden)
pub extend NativeRequestError with Eq::{not_equal}

///|
pub extend WorkflowRuntimeState with Eq::{equal}

///|
#deprecated("Use `!=` instead", skip_current_package=true)
#doc(hidden)
pub extend WorkflowRuntimeState with Eq::{not_equal}

///|
pub extend WorkflowResult with Eq::{equal}

///|
#deprecated("Use `!=` instead", skip_current_package=true)
#doc(hidden)
pub extend WorkflowResult with Eq::{not_equal}

///|
pub extend NativeMapRequest with Eq::{equal}

///|
#deprecated("Use `!=` instead", skip_current_package=true)
#doc(hidden)
pub extend NativeMapRequest with Eq::{not_equal}

///|
pub extend NativeReduceRequest with Eq::{equal}

///|
#deprecated("Use `!=` instead", skip_current_package=true)
#doc(hidden)
pub extend NativeReduceRequest with Eq::{not_equal}

///|
pub extend NativeScanRequest with Eq::{equal}

///|
#deprecated("Use `!=` instead", skip_current_package=true)
#doc(hidden)
pub extend NativeScanRequest with Eq::{not_equal}

///|
#deprecated("Use `Debug::to_repr` instead", skip_current_package=true)
#doc(hidden)
pub extend NativeValueType with @debug.Debug::{to_repr}

///|
#deprecated("Use `Debug::to_repr` instead", skip_current_package=true)
#doc(hidden)
pub extend NativeReductionKernel with @debug.Debug::{to_repr}

///|
#deprecated("Use `Debug::to_repr` instead", skip_current_package=true)
#doc(hidden)
pub extend NativeRequestError with @debug.Debug::{to_repr}

///|
#deprecated("Use `Debug::to_repr` instead", skip_current_package=true)
#doc(hidden)
pub extend WorkflowRuntimeState with @debug.Debug::{to_repr}

///|
#deprecated("Use `Debug::to_repr` instead", skip_current_package=true)
#doc(hidden)
pub extend WorkflowResult with @debug.Debug::{to_repr}

///|
#deprecated("Use `Debug::to_repr` instead", skip_current_package=true)
#doc(hidden)
pub extend NativeMapRequest with @debug.Debug::{to_repr}

///|
#deprecated("Use `Debug::to_repr` instead", skip_current_package=true)
#doc(hidden)
pub extend NativeReduceRequest with @debug.Debug::{to_repr}

///|
#deprecated("Use `Debug::to_repr` instead", skip_current_package=true)
#doc(hidden)
pub extend NativeScanRequest with @debug.Debug::{to_repr}
