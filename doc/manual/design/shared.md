# shared design

## Design goal

Every package of `luna_thread` needs to say which backend, which mode, how many
workers and what ordering it means, and every backend needs to speak the C
runtime's integer codes. `shared` is the one place where these are defined, so
that `plan`, `workflow` and the backends agree on them without depending on
each other. It has no dependencies of its own and builds on every target.

## Mathematical background

### Policies as a refined product

An execution policy is an element of the product

$$
P = B \times D \times \mathbb{Z} \times \mathbb{Z} \times O ,
$$

backend, mode, worker count, chunk size and ordering. The v1 runtime accepts
the subset

$$
P_1 = \{\, (b, d, w, c, o) \in P \mid w > 0,\ c > 0,\ b = \mathrm{Native},\ d = \mathrm{Synchronous} \,\} .
$$

`make_execution_policy` is a partial constructor $P \rightharpoonup P_1$: it
returns its argument when it lies in $P_1$ and otherwise the first violated
condition, in the order listed. `validate_policy` returns the list of all
violated conditions, so

$$
p \in P_1 \iff \operatorname{validate\_policy}(p) = [\,] .
$$

### Status codes as a section and a retraction

Let $S$ be the eight constructors of `NativeStatus` and
$\gamma = $ `native_status_code` $: S \to \mathbb{Z}$ number them $0$ to $7$.
Let $\rho = $ `native_status_from_code` $: \mathbb{Z} \to S$ invert $\gamma$ on
$\{0, \dots, 7\}$ and send every other integer to `InvalidArgument`. Then

$$
\rho \circ \gamma = \mathrm{id}_S ,
$$

so $\gamma$ is injective (a section) and $\rho$ is surjective (a retraction).
The other composite is the identity only on the image of $\gamma$:

$$
(\gamma \circ \rho)(m) =
\begin{cases}
m & 0 \le m \le 7, \\
1 & \text{otherwise.}
\end{cases}
$$

Converting a C status to `NativeStatus` and back therefore preserves codes
$0$ to $7$ and collapses the workflow statuses $8$ to $14$ to $1$.

## Design decisions

### Return the first policy error, list all policy issues

Constructing a policy is the common case, and one error message is enough to
fix a call, so `make_execution_policy` returns `Result` with the first problem.
Re-checking a stored policy happens inside workflow validation, which reports
everything at once, so `validate_policy` returns all problems. Both test the
same four conditions in the same order.

### Aborting conveniences are kept small

`ExecutionPolicy::new`, `native_policy` and `javascript_policy` unwrap the
result of `make_execution_policy`. For the native defaults this cannot fail.
For the JavaScript backend it always fails in v1, so `javascript_policy`
aborts; it exists so that code written for the planned JavaScript backend
compiles today. Code that takes policy arguments from users should call
`make_execution_policy`.

### Capabilities are declared, not probed

`RuntimeCapabilities::for_backend` returns a fixed table. Probing the running
system would need the native backend, which `shared` must not depend on, and
would differ between the `moon` build and the CMake build. The table states the
intended capabilities of each backend; the backend pages state what the current
implementation does.

### Integer-coded mirrors of the C structs

`NativeBuffer` and the three request records copy the field order and integer
encodings of the C structs in `luna_thread_runtime.h`, so that a binding can
fill them without knowing the typed records of `backend/native`. The
specification calls this correspondence the ABI layout isomorphism. The records
store values unchecked; checking belongs to the backend that sends them.

## Correctness / invariants

- **Policy subset.** Every policy returned by `make_execution_policy`,
  `ExecutionPolicy::new` or `native_policy` lies in $P_1$.
- **Status round trip.** $\rho(\gamma(s)) = s$ for every `NativeStatus` $s$, as
  derived above; the test in the [shared API](../api/shared.md) checks all eight.
- **No dependencies.** The package imports only the MoonBit core library, so
  the dependency graph of the module stays acyclic.

## Alternatives rejected

- **A typed error per backend.** One `PolicyIssue` type keeps policies
  backend-independent; the issues name the unsupported backend or mode as data.
- **A partial `native_status_from_code`.** Returning `NativeStatus?` would
  force every caller to handle codes the runtime may add later; mapping them to
  `InvalidArgument` errs on the side of failure.
- **Defining the integer codes in each backend.** The codes are part of the C
  contract, so they live in the package every backend shares.

## Boundaries

The package does not run anything, probe the system, validate the integer
request records, or describe statuses $8$ to $14$ as constructors; the
workflow runtime reports those as raw integers.
