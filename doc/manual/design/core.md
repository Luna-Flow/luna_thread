# core design

## Design goal

The root package is the facade most programs import. It should let a program
build policies, plans and workflows, run kernels and submit workflows through
one import, with sensible defaults, while the real definitions stay in the
packages that own them. It is also where the backend is chosen, so it is the
only package besides `backend/native` that depends on the C runtime.

## Constraints

- The facade imports `backend/native`, whose foreign functions exist only on
  the native target, so the facade cannot build anywhere else.
- MoonBit methods can only be defined in the package that owns the type, so the
  facade cannot add methods to `Plan`, `Workflow` or `ExecutionPolicy`.
- Every facade function must mean exactly what the function it wraps means, so
  that moving from the facade to a package import changes no behaviour.

## Main design decisions

### Free functions with defaults

The facade exposes free functions such as `map`, `workflow` and `spawn_task`
rather than methods on the imported types, because the types belong to other
packages and cannot gain methods here. Optional arguments carry the defaults,
so the common call is short: `@luna_thread.map("double", @luna_thread.i32_type(), 16)`
is a complete, valid plan. Capability helpers bind each kind to its only valid
access mode (`channel_capability` to `MoveOnly`, `mutex_capability` to
`SynchronizeOnly`, `shared_read_capability` to `ReadOnly`), which removes a
whole class of `InvalidCapabilityAccess` issues.

### Backend routing in one place

`submit_workflow` dispatches on the backend: `Native` goes to
`@native.submit_workflow`, anything else to `@workflow.submit`. Both produce the
same validated submission today, but routing through the backend package is
where execution will be attached. The direct-execution and asynchronous
functions call `backend/native` unconditionally, because it is the only
backend that executes.

### The facade is native-only

Because it imports `backend/native`, whose foreign functions exist only on the
native target, the facade declares `supported_targets = "native"`. Code that
must build everywhere imports `plan`, `shared` and `workflow` directly; they
provide everything except execution.

### Kernel defaults kept from the original interface

The kernel defaults $w = c = 1$ are the smallest valid policy values, matching
`make_policy`, but as derived below they satisfy the cover condition only for
one element. Changing them would change the meaning of existing calls; the
API and tutorial pages tell users to pass both arguments.

## Mathematical background

The facade adds no new concepts; it is a set of equations between its functions
and those of the underlying packages. With $\mathbf{d}$ the default policy
$(\mathrm{Native}, \mathrm{Synchronous}, 1, 1, \mathrm{PreserveInputOrder})$:

$$
\begin{aligned}
\texttt{@luna\_thread.map}(\ell, t, n) &= \texttt{@plan.map}(\ell, t, n, \mathbf{d}, \mathrm{PreserveInputOrder}), \\
\texttt{@luna\_thread.submit\_workflow}(w, \mathrm{Native}) &= \texttt{@workflow.submit}(w, \mathrm{Native}), \\
\texttt{@luna\_thread.execute\_map\_i32}(x, w, c) &= \texttt{@native.execute\_map\_i32}(x, w, c),
\end{aligned}
$$

and likewise for every other function. The only facts specific to the facade
are its defaults. For the kernels the defaults are $w = c = 1$, and the native
cover condition $w \ge \lceil n / c \rceil$ becomes

$$
1 \ge \left\lceil \frac{n}{1} \right\rceil = n ,
$$

so with default arguments the kernels accept only inputs of length one.

## Correctness / invariants

- **Faithful forwarding.** Each facade function returns exactly what the
  underlying function returns for the same arguments and defaults; the facade
  holds no state.
- **Defaults are valid policies.** `default_policy()` lies in the v1 policy
  subset; `make_policy` with no arguments returns `Ok(default_policy())`.
- **Single dependency on C.** Only `execute_*`, `submit_workflow_async`,
  `poll_workflow`, `wait_workflow` and `drop_workflow` reach the C runtime.

## Alternatives rejected

- **Re-exporting whole packages.** Re-exporting every name of `plan`,
  `shared` and `workflow` would duplicate their API pages; the facade keeps the
  entry points a typical program needs, and the packages remain importable.
- **Choosing the backend by target at compile time.** That would make the
  facade build on every target but silently change behaviour with the target;
  v1 makes the native requirement explicit instead.

## Boundaries

The facade does not define types, validate anything itself, execute plans,
manage thread pools, or support the JavaScript backend; it forwards to the
packages that do or will.
