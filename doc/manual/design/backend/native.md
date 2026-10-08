# backend/native design

## Design goal

`backend/native` is where `luna_thread` actually runs code in parallel. It has
two jobs: run data-parallel integer kernels on MoonBit arrays without copying
them, and run a workflow graph's synchronisation protocol on real threads. Both
are implemented in C, behind a narrow interface of integers and borrowed
arrays, so that the same runtime can later serve the JavaScript addon.

This page describes the threading model, the memory model and the mathematics
of the kernels as they are implemented in `native/src/runtime.c` and the bridge
`ffi_runtime_bridge.c`.

## Mathematical background

### Chunked evaluation

Let $x = (x_0, \dots, x_{n-1})$ be the input, $w$ the worker count and $c$ the
chunk size, with $0 < w \le n$ and $0 < c \le n$. The runtime requires the
**cover condition**

$$
w \ge k, \qquad k = \left\lceil \frac{n}{c} \right\rceil ,
$$

so that one worker can take each chunk, and splits $[0, n)$ into $k$
contiguous chunks $[s_j, s_{j+1})$ with

$$
s_0 = 0, \qquad s_{j+1} = s_j + \left\lceil \frac{n - s_j}{k - j} \right\rceil .
$$

**Chunk sizes.** Every chunk has $\lfloor n/k \rfloor$ or $\lceil n/k \rceil$
elements, and therefore at most $c$:

$$
\begin{aligned}
k \ge \frac{n}{c}
&\;\Longrightarrow\; \frac{n}{k} \le c
\;\Longrightarrow\; \left\lceil \frac{n}{k} \right\rceil \le c
&& \text{since } c \in \mathbb{Z}.
\end{aligned}
$$

The first claim is the usual balanced-partition argument: if the remaining
$r = n - s_j$ elements and $m = k - j$ chunks satisfy
$m \lfloor n/k \rfloor \le r \le m \lceil n/k \rceil$, then
$\lceil r/m \rceil$ lies between $\lfloor n/k \rfloor$ and $\lceil n/k \rceil$,
and the inequality holds again for $r - \lceil r/m \rceil$ and $m - 1$. At
$j = 0$ it holds with $r = n$, $m = k$.[^cover]

[^cover]: The code computes the chunk count as $\min(k, w)$, which equals $k$
under the cover condition. Without the condition the chunks would be larger
than $c$, so the runtime rejects it instead.

### Reductions as monoid folds

A reduction combines the elements with an associative operation $\oplus$:

$$
\operatorname{reduce}(x) = x_0 \oplus x_1 \oplus \dots \oplus x_{n-1}.
$$

Sum, minimum and maximum on the integers are associative and commutative.
Associativity is what makes chunking correct: with chunk results
$P_j = x_{s_j} \oplus \dots \oplus x_{s_{j+1}-1}$,

$$
P_0 \oplus P_1 \oplus \dots \oplus P_{k-1}
= x_0 \oplus x_1 \oplus \dots \oplus x_{n-1}
$$

by the generalised associative law, whatever $w$ and $c$ are. Minimum and
maximum seed each chunk with its first element, so they only need a semigroup;
this is one reason the runtime requires $n > 0$.

### Prefix sums by blocks

The scan computes the inclusive prefix sums $y_i = \sum_{t=0}^{i} x_t$ in three
phases. With $S_j$ the sum of chunk $j$:

1. In parallel, each chunk computes its local prefix sums
   $L_j(i) = \sum_{t=s_j}^{i} x_t$ for $s_j \le i < s_{j+1}$, writing them to
   the output, and its total $S_j = L_j(s_{j+1} - 1)$.
2. Sequentially, the carries $C_0 = 0$ and $C_j = C_{j-1} + S_{j-1}$.
3. In parallel, each chunk adds its carry: $y_i = C_j + L_j(i)$.

Phase 3 is correct because, by induction on $j$, $C_j = \sum_{t=0}^{s_j - 1} x_t$:

$$
\begin{aligned}
C_{j+1} = C_j + S_j
&= \sum_{t=0}^{s_j - 1} x_t + \sum_{t=s_j}^{s_{j+1} - 1} x_t
= \sum_{t=0}^{s_{j+1} - 1} x_t, \\
C_j + L_j(i) &= \sum_{t=0}^{s_j - 1} x_t + \sum_{t=s_j}^{i} x_t = \sum_{t=0}^{i} x_t = y_i .
\end{aligned}
$$

The scan does $2n + k$ additions; with $k$ workers its critical path is
$O(n/k + k)$, against $O(n)$ for the sequential loop.

## Design decisions

### Checked integer arithmetic

The kernels work on $\mathbb{Z}/2^{32}$ and $\mathbb{Z}/2^{64}$, where `+`
wraps around. The runtime instead treats them as the integers and refuses to
return a wrapped value: every addition $a + b$ is checked before it is made,

$$
b > 0 \wedge a > \mathrm{MAX} - b \quad\text{or}\quad b < 0 \wedge a < \mathrm{MIN} - b
\;\Longrightarrow\; \text{overflow},
$$

and these tests do not overflow themselves. The map kernel ($x \mapsto 2x$)
first checks every element in one parallel pass and writes only if none
overflows, so on failure the output is untouched.

The consequence is that a successful result is exact: each machine addition
that was performed had an in-range true result, so it equals the integer
addition, and by induction the returned sum or prefix equals
$\sum x_t$ in $\mathbb{Z}$.

The cost is that checked addition is a partial operation and is **not**
associative: whether some partial sum leaves the range depends on the
bracketing. With $x = (-1, 0, \mathrm{MAX}, 1)$:

$$
\begin{aligned}
k = 1:&\quad ((-1 + 0) + \mathrm{MAX}) + 1 = \mathrm{MAX} && \text{succeeds}, \\
k = 2:&\quad (-1 + 0) + (\mathrm{MAX} + 1) && \text{fails in the second chunk}.
\end{aligned}
$$

So the values are independent of $w$ and $c$, but the set of accepted inputs
is not. The alternative, wrapping arithmetic, would make every result defined
and chunking-independent, but silently wrong as an integer; the runtime chose
exactness.

### Fixed kernels in C

Plans can name `Map` and reduction kernels, but MoonBit closures cannot cross
the C interface and run on C threads. The runtime therefore implements a fixed
set of kernels in C: doubling, sum, minimum, maximum and prefix sum, for 32-
and 64-bit integers. The facade wraps the 32-bit doubling, sum and prefix sum;
the others are reachable through the `ffi_*` declarations.

### Borrowed arrays, caller-allocated output

The MoonBit side passes `FixedArray` payloads to C with `#borrow`: C reads the
input and writes the output in place and takes no ownership, so no copy is made
and no reference count changes. The typed wrappers allocate the output with
`FixedArray::make` before the call. Reductions return their value directly;
the bridge passes a stack variable as the one-element output.

### One scheduler lock for workflows

The workflow runtime keeps all scheduling state, the ready queue, dependency
counters, channel slots, mutex flags and barrier counters, under a single
`pthread_mutex_t`, and workers execute each node while holding it. This makes
every node step atomic with respect to the others without any per-capability
locks, at the price that non-compute nodes never run simultaneously; they are
bookkeeping steps that take constant time.

## The threading model

### Kernels

Each kernel runs its chunk loop as an OpenMP `parallel for` with
`num_threads(w)` when the runtime is compiled with OpenMP, one iteration per
chunk. Without OpenMP the pragmas are ignored and `select_thread_count`
returns $1$, so the same chunks run one after another on the calling thread.
The `moon` build compiles the native stubs without OpenMP flags, so from
MoonBit the kernels currently run sequentially; the CMake build of `native/`
enables OpenMP. Because the chunking is the same in both builds, the results
and the overflow behaviour are the same.

### Workflows

`submit_workflow_async` starts $w + 1$ POSIX threads: $w$ workers and one
**compute lane**. Scheduling is Kahn's topological sort run by a pool:

- Each node $v$ has a counter of unfinished predecessors, initially its
  in-degree. Nodes with counter $0$ go into a FIFO ring buffer of capacity
  $|V|$.
- A worker waits on the scheduler's condition variable until the queue is
  non-empty, dequeues a node and executes it. Completing a node decrements the
  counters of its successors and enqueues those that reach $0$.
- A compute node is handed to the compute lane, and the worker waits for it.
  In v1 the lane only checks the node kind and reports success; the plan is not
  executed.
- When all $|V|$ nodes have completed the state becomes `Completed`; the first
  failing node sets `Failed`, its status and `failed_node_id`. Both wake every
  waiting thread so that the pool shuts down.

There are no per-thread queues and no work stealing: all workers share one
queue, and FIFO order with execution under the lock makes the order in which
ready nodes run the order in which they became ready.

### Node semantics

| Node | Effect when executed |
| --- | --- |
| `Spawn`, `Join`, `ReadShared`, `WriteShared` | Completes immediately; no data moves. |
| `Send` | Blocks if the channel slot is full, otherwise fills it. |
| `Recv` | Blocks if the slot is empty, otherwise empties it. |
| `Lock` | Blocks if the mutex flag is set, otherwise sets it. |
| `Unlock` | Fails with status 12 if the flag is clear, otherwise clears it. |
| `Wait` | Blocks until a `Signal` on the same condition variable wakes it. |
| `Signal` | Wakes one blocked `Wait`, if any; otherwise the signal is lost. |
| `Barrier` | Blocks until every barrier node of its group has arrived. |

A channel is a slot of capacity one, and capabilities carry no payload: the
runtime enforces the protocol, not the transfer of data.

A barrier's group is the set of `Barrier` nodes with the same capability and
the same depth $d(v)$, the length of the longest path from a source to $v$:

$$
d(v) = \max\bigl(\{0\} \cup \{\, d(u) + 1 \mid (u, v) \in E \,\}\bigr).
$$

The runtime computes $d$ by $|V|$ rounds of relaxation over all edges, which is
enough because a longest path in an acyclic graph has at most $|V| - 1$ edges.
A group with fewer than two nodes fails with status 14 (`BARRIER_BROKEN`).

## The memory model

For kernels, the chunks partition $[0, n)$, and in each parallel phase
iteration $j$ writes only output indices in $[s_j, s_{j+1})$ and its own
`partials[j]` or `summaries[j]` cell. Distinct iterations therefore write
disjoint locations, and there is no data race. The end of an OpenMP
`parallel for` is a barrier, so the sequential carry phase sees every
phase-one write, and phase three sees the carries. The MoonBit caller is
blocked for the whole call, so no MoonBit code touches the arrays while C
threads run, and the borrowed arrays stay alive because the caller still holds
them.

For workflows, every access to shared scheduler state happens under the
scheduler mutex, and condition-variable waits re-acquire it, so all such
accesses are ordered. `poll_workflow` takes the same mutex to copy a
consistent snapshot.

## Correctness / invariants

- **Kernel results.** When a kernel succeeds, the doubled values, the sum and
  the prefix sums equal their values in $\mathbb{Z}$, independent of $w$ and
  $c$, as derived above.
- **Validation before work.** Every kernel checks null pointers, positive
  sizes, $w \le n$, $c \le n$, buffer lengths and the cover condition before it
  allocates or computes, and returns status 1 otherwise (7 for a null
  pointer).
- **Workflow admission.** Before starting threads the runtime requires a
  positive worker and node count, capabilities for the nodes that need them
  with matching kinds, no `RwLock`, `Semaphore` or `Opaque` capability, no self
  edge, existing edge endpoints, and acyclicity, which it checks completely by
  Kahn's algorithm: a finite graph is acyclic exactly when repeatedly removing
  nodes without incoming edges removes them all.
- **Termination.** If no `Send`, `Recv` or `Lock` node ever blocks, every
  `Wait` is signalled after it blocks, and every barrier group has at least two
  nodes, every node completes once and the workflow reaches `Completed` or
  `Failed`.

## Known defects

These behaviours of the current branch contradict the intent of the code and
are tracked for fixing:

- **Request lifetime.** `luna_mbt_workflow_submit_async` builds the request on
  its stack and frees the capability, node and edge arrays right after the
  runtime starts, but the worker threads keep a pointer to that request.
  Workflow runs read freed memory and crash intermittently.
- **Lost wake-ups.** Only `Signal` and a completed barrier re-enqueue blocked
  nodes. A `Send`, `Recv` or `Lock` that blocks is never retried, so the
  workflow never finishes and `wait_workflow` does not return.
- **Errors without a channel.** A rejected workflow becomes an empty handle
  reported as `Ok`, and `execute_reduce_sum_i32` reports failures as `0`.
- **Runtime identity.** `supports_openmp()` is the constant `true`, while the
  `moon` build has no OpenMP.

## Alternatives rejected

- **Work-stealing deques.** Per-worker deques pay off when tasks are many and
  uneven. Workflow nodes here are constant-time protocol steps executed under
  one lock, so a shared FIFO is simpler and enough; data parallelism is left to
  OpenMP inside each kernel.
- **Executing MoonBit closures on C threads.** The MoonBit runtime gives no
  guarantee that its objects may be used from foreign threads, so the kernels
  are fixed C functions instead.
- **Copying arrays across the interface.** Copies would make the memory model
  trivial but double the memory traffic of every kernel; borrowing plus
  disjoint writes gives the same safety.
- **Wrapping arithmetic.** Rejected in favour of exact results, as derived
  above.

## Boundaries

The backend does not execute plans, user-defined kernels, floating-point data
or `Bytes`; it does not move data through channels or shared capabilities; it
does not implement read-write locks or semaphores; it does not detect
deadlocks or offer timeouts; and it does not build for any target but
`native`.
