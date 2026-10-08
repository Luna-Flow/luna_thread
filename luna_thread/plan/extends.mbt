///|
pub extend PlanKind with Eq::{equal}

///|
#deprecated("Use `!=` instead", skip_current_package=true)
#doc(hidden)
pub extend PlanKind with Eq::{not_equal}

///|
pub extend ValueType with Eq::{equal}

///|
#deprecated("Use `!=` instead", skip_current_package=true)
#doc(hidden)
pub extend ValueType with Eq::{not_equal}

///|
pub extend ReductionKernel with Eq::{equal}

///|
#deprecated("Use `!=` instead", skip_current_package=true)
#doc(hidden)
pub extend ReductionKernel with Eq::{not_equal}

///|
pub extend ValidationIssue with Eq::{equal}

///|
#deprecated("Use `!=` instead", skip_current_package=true)
#doc(hidden)
pub extend ValidationIssue with Eq::{not_equal}

///|
pub extend DataDomain with Eq::{equal}

///|
#deprecated("Use `!=` instead", skip_current_package=true)
#doc(hidden)
pub extend DataDomain with Eq::{not_equal}

///|
pub extend Plan with Eq::{equal}

///|
#deprecated("Use `!=` instead", skip_current_package=true)
#doc(hidden)
pub extend Plan with Eq::{not_equal}

///|
#deprecated("Use `Debug::to_repr` instead", skip_current_package=true)
#doc(hidden)
pub extend PlanKind with @debug.Debug::{to_repr}

///|
#deprecated("Use `Debug::to_repr` instead", skip_current_package=true)
#doc(hidden)
pub extend ValueType with @debug.Debug::{to_repr}

///|
#deprecated("Use `Debug::to_repr` instead", skip_current_package=true)
#doc(hidden)
pub extend ReductionKernel with @debug.Debug::{to_repr}

///|
#deprecated("Use `Debug::to_repr` instead", skip_current_package=true)
#doc(hidden)
pub extend ValidationIssue with @debug.Debug::{to_repr}

///|
#deprecated("Use `Debug::to_repr` instead", skip_current_package=true)
#doc(hidden)
pub extend DataDomain with @debug.Debug::{to_repr}

///|
#deprecated("Use `Debug::to_repr` instead", skip_current_package=true)
#doc(hidden)
pub extend Plan with @debug.Debug::{to_repr}
