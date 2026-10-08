# workflow design

## Design goal

Data-parallel plans cover one operation at a time. Real programs also spawn and
join tasks, pass work through channels, and protect shared state with locks.
The `workflow` package gives these a single description: a task graph whose
nodes are typed steps, whose resources are explicit capabilities, and whose
edges fix the order of execution. The graph is data, so it can be validated in
MoonBit on any target before a runtime executes it.

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

The edges define the relation $u \prec v$, "there is a path from $u$ to $v$".
An execution order is a sequence of all nodes in which $u$ comes before $v$
whenever $u \prec v$, a **topological order**. Such an order exists exactly
when $(V, E)$ has no directed cycle: a cycle $v_0 \to \dots \to v_m = v_0$
would require $v_0$ before itself, and conversely Kahn's algorithm builds an
order for every acyclic graph by repeatedly removing a node without incoming
edges.

## Design decisions

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

### The MoonBit cycle check is partial

`validate` reports `CyclicDependency` when (a) the graph has nodes but none
without incoming edges, or (b) two edges point in opposite directions between
the same pair of nodes. Both conditions imply a cycle when every edge joins
existing nodes:

- (b) is a cycle of length two.
- For (a), walk backwards from any node along incoming edges. Every node has
  one, so the walk never stops; with $|V|$ nodes it must repeat a node within
  $|V| + 1$ steps, and the repeated segment is a cycle.

The converse fails: in $1 \to 2 \to 3 \to 4 \to 2$, node $1$ has no incoming
edge and no pair of edges is opposite, so `validate` reports nothing although
$2 \to 3 \to 4 \to 2$ is a cycle. The native runtime runs Kahn's algorithm,
which removes $1$ and then finds no node to remove among $\{2, 3, 4\}$, and
rejects the graph. An edge from an unknown node also counts as an incoming
edge for (a), so a graph whose only incoming edges come from unknown ids gets a
`CyclicDependency` next to its `InvalidNodeReference` issues.

## Correctness / invariants

- **Soundness of acceptance.** If `validate` returns no issue, the workflow is
  well formed in the sense above, except possibly for a cycle of length three
  or more that is reachable from a source.
- **Soundness of rejection.** Every issue names a real violation, with the one
  `CyclicDependency` caveat for edges from unknown nodes.
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
