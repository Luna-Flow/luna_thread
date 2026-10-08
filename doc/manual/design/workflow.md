# workflow design

## Design goal

Data-parallel plans cover one operation at a time. Real programs also spawn and
join tasks, pass work through channels, and protect shared state with locks.
The `workflow` package gives these a single description: a task graph whose
nodes are typed steps, whose resources are explicit capabilities, and whose
edges fix the order of execution. The graph is data, so it can be validated in
MoonBit on any target before a runtime executes it.

## Constraints

- The package must build on every target, so a workflow is pure data that a
  runtime interprets later; nothing in it may refer to threads or C objects.
- A workflow must embed plans unchanged, so that a compute node is checked by
  the same rules as a standalone plan.
- The native runtime receives the graph as flat integer arrays, so nodes and
  capabilities are identified by integer ids rather than by references.

## Main design decisions

### Capabilities are declared, nodes refer to them by id

Synchronisation resources exist independently of the steps that use them: two
nodes that send and receive must agree on one channel. Declaring a capability
once and referring to it by id makes that agreement explicit and checkable,
and gives the runtime a dense table of resources to allocate. The access mode
records the intent of the declaration, such as `MoveOnly` for a channel or
`ReadOnly` for a shared view, so that `validate` can reject a `WriteShared`
node on a read-only buffer.

### Every edge kind orders the same way

`DataDependency`, `ControlDependency`, `OwnershipTransfer` and
`SynchronizationDependency` all mean $u$ completes before $v$ starts. The
kind documents why the edge exists, and the specification gives ownership
transfer further meaning, but v1 checks and schedules all edges alike, so the
order relation $\prec$ does not depend on the kinds.

### Builders mutate in place

`Workflow` stores its capabilities, nodes and edges in `Array`s, and
`add_capability`, `add_node` and `add_edge` push onto them and return the same
workflow. This makes chained construction cheap, $O(1)$ amortised per step, but
it is not a persistent builder: after `let b = a.add_node(n)`, `a` and `b` are
the same value and both contain `n`. Code that needs two variants must build
two workflows.

### Validation is layered

`validate` in MoonBit checks the whole data model on every target: policy,
capability kinds and access modes, node and capability references, edge
endpoints, the plans of compute nodes, and cycles. The native runtime checks
again what it relies on when a workflow is submitted. The two layers agree on
most rules but not all:

| Rule | `validate` | Native runtime |
| --- | --- | --- |
| `RwLock`, `Semaphore` capabilities | accepted | rejected (status 8) |
| `Lock` and `Unlock` on an `RwLock` | accepted | rejected |
| Access modes, duplicate ids, compute plans | checked | not checked |
| Cycles | partial (below) | complete (status 9) |

The MoonBit layer reports every issue, so a user sees all problems at once;
the native layer stops at the first, because it only decides whether to start.

### A cheap cycle check in MoonBit, a complete one in C

`validate` looks for cycles with two local tests instead of a topological
sort, and the native runtime runs Kahn's algorithm before it starts any
thread. The MoonBit test never reports a cycle that is not there (for graphs
whose edges join existing nodes), but it misses many cycles; the derivation is
under [the MoonBit cycle check](#the-moonbit-cycle-check) below.

## Mathematical background

A workflow is a triple $W = (C, V, E)$ of capabilities, nodes and edges.

- Each capability $\kappa \in C$ has an id, a kind $k(\kappa) \in K$ and an
  access mode $a(\kappa) \in M$.
- Each node $v \in V$ has an id, a kind $t(v) \in T$ and optionally a
  capability $\operatorname{cap}(v)$.
- Each edge $(u, v) \in E$ says that $v$ may start only after $u$ has
  completed.

Two relations type the graph. $\mathrm{Acc} \subseteq K \times M$ lists the
valid access modes of each capability kind, and
$\mathrm{Use} \subseteq T \times K$ the capability kinds each node kind may
use (both tables are in the [workflow API](../api/workflow.md)). A workflow is
**well formed** when ids are unique, edges join existing distinct nodes, and

$$
\forall \kappa \in C:\ (k(\kappa), a(\kappa)) \in \mathrm{Acc},
\qquad
\forall v \in V \text{ that needs one}:\ (t(v), k(\operatorname{cap}(v))) \in \mathrm{Use}.
$$

The edges define the relation $u \prec v$, "there is a non-empty path from $u$
to $v$". An execution order is a sequence of all nodes in which $u$ comes
before $v$ whenever $u \prec v$, a **topological order**.

### Topological orders and Kahn's algorithm

**Claim.** A finite graph $(V, E)$ has a topological order exactly when it has
no directed cycle.

If $v_0 \to v_1 \to \dots \to v_m = v_0$ is a cycle with $m \ge 1$, an order
would place $v_0$ before $v_1$, $v_1$ before $v_2$, and so on, hence $v_0$
before itself; no order exists.

Conversely, suppose there is no cycle. Kahn's algorithm keeps a set $R$ of
remaining nodes, initially $V$, and repeatedly removes a node of $R$ that has
no incoming edge from $R$, appending it to the order. Each node removed has all
its predecessors already in the order, so whenever the algorithm removes every
node, the result is a topological order. It cannot get stuck with
$R \neq \emptyset$: then every $v \in R$ has a predecessor in $R$, and walking
backwards $v = u_0 \leftarrow u_1 \leftarrow u_2 \leftarrow \cdots$ inside $R$
visits $|R| + 1$ nodes after $|R|$ steps, so some node repeats,
$u_i = u_j$ with $i < j$, and $u_j \to u_{j-1} \to \dots \to u_i$ is a cycle.

The same argument shows that Kahn's algorithm *decides* acyclicity: it removes
all of $V$ if and only if the graph is acyclic. The C function
`workflow_has_cycle` implements it by repeated passes that remove every node
whose in-degree from the remaining nodes is zero, in $O(|V| \cdot |V| \cdot |E|)$
per pass and at most $|V|$ passes; it returns status `9`
(`RUNTIME_BROKEN`) when nodes remain.

### The MoonBit cycle check

Let $\deg^-(v)$ count the edges whose target is $v$, including edges whose
source is not a node of the workflow. `validate` reports `CyclicDependency`
exactly when

$$
\underbrace{V \neq \emptyset \;\wedge\; \forall v \in V:\ \deg^-(v) > 0}_{(a)}
\qquad\text{or}\qquad
\underbrace{\exists\, e, e' \in E:\ e.\mathit{from} = e'.\mathit{to} \wedge e.\mathit{to} = e'.\mathit{from}}_{(b)} ,
$$

where $e = e'$ is allowed, so a self edge satisfies (b).

**Soundness.** Assume every edge joins existing nodes. If (b) holds with
$e = e'$, then $e$ is a self edge, a cycle of length one. If $e \neq e'$, then
$e.\mathit{from} \to e.\mathit{to} \to e.\mathit{from}$ is a cycle of length
two. If (a) holds, the backward walk of the previous section runs inside all of
$V$ and finds a cycle. So every report names a real cycle.

**Incompleteness.** Suppose some node $s$ has $\deg^-(s) = 0$ and no two edges
are opposite. Then (a) fails because of $s$ and (b) fails by assumption, so
nothing is reported, whatever the rest of the graph looks like. Any cycle of
length $m \ge 3$ without a chord in the reverse direction escapes, and $s$
need not be connected to it. In the graph with nodes $1, 2, 3, 4$ and edges
$2 \to 3 \to 4 \to 2$, node $1$ is isolated, $\deg^-(1) = 0$, and `validate`
reports nothing, while Kahn's algorithm removes $1$, finds no node of
in-degree zero among $\{2, 3, 4\}$ and rejects the graph. Without node $1$,
condition (a) holds and the cycle is reported.

**Unknown sources.** When an edge starts at an id that is not a node, it
still counts in $\deg^-$, so (a) can hold without a cycle: one node $1$ with
the edge $99 \to 1$ gets `CyclicDependency` next to `InvalidNodeReference`
and `InvalidDependency`. This is the only false report, and it only occurs
together with the issues that explain it.

## Correctness / invariants

- **Soundness of acceptance.** If `validate` returns no issue, the workflow is
  well formed in the sense above, except possibly for a cycle of length three
  or more in a graph that has at least one node without incoming edges; such a
  cycle need not be connected to that node.
- **Soundness of rejection.** Every issue names a real violation, with the one
  `CyclicDependency` caveat for edges from unknown nodes. `InvalidPolicy` never
  occurs for workflows built outside these packages, because their policies
  are always valid (see the [shared design](shared.md)).
- **Submission.** `submit(w, backend)` is accepted exactly when
  `validate(w)` is empty and `backend` is `Native`; it never sets `completed`.
- **Complexity.** `validate` runs in
  $O(|V|^2 + |C|^2 + |E|^2 + |V| \cdot |C| + |V| \cdot |E|)$: duplicate
  detection filters the whole array for each element, endpoint and in-degree
  lookups scan the node and edge arrays, and the opposite-edge test compares
  all pairs of edges.

## Alternatives rejected

- **Capabilities embedded in nodes.** A channel stored inside each `Send` node
  could not be shared with the matching `Recv`.
- **Typed edges with different scheduling.** Giving each edge kind its own
  scheduling rule would make the order relation depend on runtime policy;
  v1 keeps one rule.
- **A persistent builder.** Copying the arrays on every `add_*` would make
  construction quadratic for the convenience of keeping old versions.
- **Full cycle detection in MoonBit.** A topological sort in `validate` would
  close the gap described above; the current check is cheaper and the native
  runtime catches the remaining cases. The gap is a candidate for a fix.

## Boundaries

The package does not schedule or execute workflows, move data between nodes,
check that blocking nodes are matched (that a `Recv` has a `Send` that runs
first), detect deadlocks, or give edge kinds different meanings.
