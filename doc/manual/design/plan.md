# plan design

## Design goal

A plan states *what* data-parallel operation to perform, on what input shape,
under which policy, without saying *how* or running it. Keeping this as plain,
comparable data lets `luna_thread` validate work before it reaches a runtime,
embed it in workflows, and translate it for different backends. The package
must stay backend-independent and build on every target.

## Mathematical background

Let the input be a sequence $x = (x_0, \dots, x_{n-1}) \in A^n$ with $n > 0$.
The four plan kinds denote these functions:

$$
\begin{aligned}
\operatorname{map}_f(x) &= (f(x_0), \dots, f(x_{n-1})) , \\
\operatorname{reduce}_\oplus(x) &= x_0 \oplus x_1 \oplus \dots \oplus x_{n-1} , \\
\operatorname{scan}_\oplus(x) &= (y_0, \dots, y_{n-1}), \quad y_i = x_0 \oplus \dots \oplus x_i , \\
\operatorname{mapreduce}_{f,\oplus}(x) &= \operatorname{reduce}_\oplus(\operatorname{map}_f(x)) .
\end{aligned}
$$

A reduction kernel must be **associative**, $(a \oplus b) \oplus c = a \oplus (b
\oplus c)$, so that the bracketing a parallel runtime chooses does not matter.
The three kernels of v1 are commutative and associative on the integers:

| Kernel | $a \oplus b$ | Identity |
| --- | --- | --- |
| `Sum` | $a + b$ | $0$ |
| `Min` | $\min(a, b)$ | none in $\mathbb{Z}$; the largest value of a fixed-width type |
| `Max` | $\max(a, b)$ | none in $\mathbb{Z}$; the smallest value of a fixed-width type |

## Design decisions

### Plans are data, not closures

The plan records the kind, the element type, the length, the policy, an
optional named kernel and the ordering, and nothing executable. A closure
could express any $f$ and $\oplus$, but it cannot be compared, inspected,
validated, or passed to C threads. Named kernels can be checked against what a
runtime implements: `reduction_kernel_is_supported_in_v1` accepts exactly the
kernels with a C implementation, and `Custom(name)` keeps a place for kernels
that a later runtime may register.

### Ordering is a property of the kind

`OrderingGuarantee` says whether results must keep input positions. For a
reduction with a commutative and associative $\oplus$, the result is the same
for every permutation $\pi$ of the input:

$$
x_{\pi(0)} \oplus \dots \oplus x_{\pi(n-1)} = x_0 \oplus \dots \oplus x_{n-1},
$$

by the generalised commutative law, so `RelaxedOrder` is safe for `Reduce` and
`MapReduce`, and for `Map` it only permits results to be produced out of order.
A scan is different: $y_i$ depends on which elements come before position
$i$. For $x = (1, 2)$ and the swap $\pi$, the sums are

$$
\operatorname{scan}_+(1, 2) = (1, 3) \neq (2, 3) = \operatorname{scan}_+(2, 1),
$$

so a scan has no meaning without input order. `scan` therefore always sets
`PreserveInputOrder`, and `validate` reports both `UnsupportedOrdering` and
`ScanRequiresStableOrdering` for a hand-built relaxed scan.

### The v1 subset is checked, not encoded in types

`ValueType` lists `F32`, `F64`, `Bytes` and `Opaque`, and `ExecutionPolicy`
can name the JavaScript backend and asynchronous mode, although v1 supports
none of them. The types describe the whole model of the specification;
`validate` decides what the current runtime accepts. When a runtime grows, the
predicates change and user code that builds plans does not.

Integer element types are also the ones for which chunked reduction is
well-defined. Floating-point addition is not associative: in `Double`,

$$
(0.1 + 0.2) + 0.3 = 0.6000000000000001 \qquad\text{but}\qquad 0.1 + (0.2 + 0.3) = 0.6 ,
$$

so a parallel sum of `F64` data would depend on the worker count and chunk
size. Supporting it needs a decision about which bracketing to promise, which
v1 does not make.

### Validation reports every issue

`validate` returns an array of all issues rather than the first one, so a
caller can show every problem of a plan together, and a workflow can wrap each
one as `InvalidComputePlan`. The issues are independent tests, listed in a
fixed order. `is_runnable` is the conjunction of their negations:

$$
\operatorname{is\_runnable}(p) \iff \operatorname{validate}(p) = [\,] .
$$

### Size checks stop short of the cover condition

`validate` rejects $c > n$ and $w > n$ because no runtime can use more chunks
than elements. It does not check the native cover condition
$w \ge \lceil n / c \rceil$, which belongs to one backend's chunking strategy
(see the [native backend design](backend/native.md)). Backends check their own
conditions when they build requests or run kernels.

## Correctness / invariants

- **Builders fix the kind.** `map`, `reduce`, `scan` and `map_reduce` produce
  plans of the corresponding kind; `reduce` and `map_reduce` always carry a
  kernel; `scan` and `reduce` always preserve order.
- **Validation is total and pure.** `validate` terminates for every plan, has
  no effects, and depends only on the plan's fields.
- **Supported plans name implemented kernels.** If
  $\operatorname{validate}(p) = [\,]$ and $p$ reduces, its kernel is `Sum`,
  `Min` or `Max` and its element type is `I32` or `I64`, the combinations the C
  runtime implements.
- **Equality is structural.** Two plans are equal exactly when all fields are
  equal, so plans can serve as keys and test expectations.

## Alternatives rejected

- **A generic `Plan[T]`.** Typing the element would push the element type into
  every workflow node and backend signature, and the C interface would still
  need a runtime tag. A `ValueType` tag keeps plans of different element types
  in one array.
- **Separate types per kind.** `MapPlan`, `ReducePlan` and so on would encode
  "reduce has a kernel" in the type, but workflows and requests would need a
  sum type over them anyway; `PlanKind` plus validation is that sum type.
- **Validation inside the builders.** Builders that return `Result` would make
  the hand-built plans that tests and tools need impossible to express.

## Boundaries

The package does not execute plans, hold input data, allocate buffers, choose
chunk sizes, check backend-specific conditions, or describe user-defined
functions; the map function is implied by the backend (doubling in the native
backend), not stored in the plan.
