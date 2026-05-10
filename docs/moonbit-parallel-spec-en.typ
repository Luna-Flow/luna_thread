#import "template/jmlr-paper-template.typ": jmlr-paper, diagram-box, diagram-panel, down-arrow, split-arrows

#show: jmlr-paper.with(
  title: [A Normative Specification for a MoonBit Parallel FFI Library],
  subtitle: [Part I defines the engineering contract for plans, ownership, and separation-safe scheduling],
  authors: [Zhehao Zhu],
  affiliation: [Luna-Flow],
  email: [GitHub: KCN-judu],
  abstract: [
    This document specifies a MoonBit parallel FFI library as a contract over plan
    representation, ownership transfer, and concurrent buffer safety. The semantic core is
    not a redefinition of `map` and `reduce` as elementary functions, but a precise
    engineering account of three boundary-critical questions: how MoonBit constructs a pure parallel plan, how
    that plan crosses the FFI boundary as an ABI-constrained payload, and how the C
    runtime executes chunked parallel work without data races or lifetime violations. Part
    I defines a plan ADT, layout isomorphism constraints, a linear ownership state
    machine, borrow and transfer rules, and separation checks for chunk
    scheduling. Part II states realization and conformance obligations for native and
    JavaScript targets. Part III refines those obligations into implementation-level
    conformance checks for exceptional control flow, byte-level layout validation, safe
    operator admissibility, and fail-closed validation scenarios. The English text is
    authoritative; the Chinese text is a strict mirror.
  ],
  keywords: [MoonBit, FFI, OpenMP, separation safety, linear ownership, ABI, engineering specification],
)

= Part I: Semantic Core

== Normative Scope

This specification defines the version-1 contract of a MoonBit parallel library across
three layers:

- a MoonBit facade that constructs pure parallel plans;
- a backend-specific FFI boundary that lowers those plans into ABI-constrained payloads;
- a shared C runtime that interprets payloads as chunked fork-join executions.

Normative force is limited to:

- the algebraic shape of the MoonBit-side plan;
- the exact classes of values that may cross the FFI boundary;
- the layout isomorphism obligations required for zero-copy or borrowed views;
- the linear ownership state transitions between MoonBit and C-visible heaps;
- the separation-logic obligations required for race-free chunk scheduling; and
- the conformance obligations for faithful native and JavaScript realizations.

Scheduler heuristics, OpenMP tuning details, and local optimization strategy are
non-normative unless they affect the observable ownership, layout, or race-safety
contract.

== Notation and Meta-Level Conventions

We use the following notation throughout:

- `H_M` for the MoonBit heap and `H_C` for the C/host-visible heap;
- $Gamma$ for the ownership-resource context carried across the FFI boundary;
- $b$ for a buffer identity, `v` for a view, $p$ for a plan, $d$ for a runtime
  descriptor;
- `mapsto` for partial meta-level evaluation;
- $upright("Own_M")(b)$, $upright("Borrow_C")(b)$, $upright("Own_C")(b)$ for ownership
  states;
- $Gamma -> Gamma'$ for one ownership transition step;
- `P * Q` for separation conjunction over disjoint heap fragments;
- `Interval(i, j)` for half-open index intervals `[i, j)`;
- `Chunks(n, m)` for a partition of `[0, n)` into `m` subintervals;
- $upright("Den")(p)$ for plan denotation;
- $t tack.l p mapsto q$ for lowering a MoonBit plan $p$ on target $t$ to payload $q$;
- $upright("parse")(t, q) mapsto d$ for wrapper parsing into runtime descriptor $d$;
- $upright("exec")(d) = y$ for runtime execution of descriptor $d$.

== Semantic Plan Calculus

The facade is a pure plan algebra. Its constructors carry enough information for the
lowering and execution layers to interpret parallel work without crossing a function-value
or runtime-state boundary.

#figure(
  $
    text("ScalarKind") ::= & "Int" \
                         |   & "UInt" \
                         |   & "Int64" \
                         |   & "UInt64" \
                         |   & "Float" \
                         |   & "Double"
  $,
  caption: [Scalar family.],
)

#figure(
  $
    text("Schedule") ::= & "Static" \
                      |   & "Dynamic" \
                      |   & "Guided"
  $,
  caption: [Schedule class.],
)

#figure(
  $
    text("RuntimeConfig") ::= & "{" \
                              & quad text("threads") ":" text("Nat") "," \
                              & quad text("chunk") ":" text("Nat") "," \
                              & quad text("schedule") ":" text("Schedule") \
                              & "}"
  $,
  caption: [Runtime configuration record.],
)

#figure(
  $
    text("AccessMode") ::= & "ReadOnly" \
                        |   & "WriteOnly" \
                        |   & "ReadWrite"
  $,
  caption: [Boundary access mode.],
)

#figure(
  $
    text("BufferRef") ::= & "(" text("BufId") "," text("ScalarKind") "," text("Len") "," text("AccessMode") "," text("LayoutWitness") ")"
  $,
  caption: [Facade-level buffer reference.],
)

#figure(
  $
    text("OutRef") ::= & "(" text("BufId") "," text("ScalarKind") "," text("Len") "," text("LayoutWitness") ")"
  $,
  caption: [Facade-level output reference.],
)

#figure(
  $
    text("LawClass") ::= & "StrictAssoc" \
                      |   & "DeterministicTree"
  $,
  caption: [Reduction-law class.],
)

#figure(
  $
    text("MonoidLaw") ::= & "(" text("LawClass") "," text("OpId") "," text("IdentityId") "," "AssocWitness" ")"
  $,
  caption: [Monoid descriptor.],
)

#figure(
  $
    text("Plan") ::= & text("MapPlan") "(" text("RuntimeConfig") "," text("OpId") "," text("BufferRef") "," text("BufferRef") ")" \
                   | & text("ReducePlan") "(" text("RuntimeConfig") "," text("MonoidLaw") "," text("BufferRef") "," text("OutRef") ")" \
                   | & text("ScanPlan") "(" text("RuntimeConfig") "," text("MonoidLaw") "," text("BufferRef") "," text("BufferRef") ")" \
                   | & text("MapReducePlan") "(" text("RuntimeConfig") "," text("OpId") "," text("MonoidLaw") "," text("BufferRef") "," text("OutRef") ")"
  $,
  caption: [Parallel plan ADT.],
)

Version 1 forbids arbitrary MoonBit function values and arbitrary JavaScript host
functions from entering the plan.

*Definition (Constructor Shape Obligations).*
Write $upright("ShapeOK")(p)$ iff:

- for `MapPlan(cfg, op, src, dst)`, `Len(src) = Len(dst)` and `dst` is writable;
- for `ReducePlan(cfg, mu, src, out)`, `Len(out) = 1`, `ScalarKind(out) = ScalarKind(src)`,
  and `out` is the unique result location of the reduction;
- for `ScanPlan(cfg, mu, src, dst)`, `Len(src) = Len(dst)`, `ScalarKind(src) =
  ScalarKind(dst)`, and `dst` is writable;
- for `MapReducePlan(cfg, op, mu, src, out)`, `Len(out) = 1`, `out` is writable, and the
  mapped element type admitted by `op` matches the reduction element type required by
  `mu`.

*Definition (Plan Denotation).*
Write $upright("Den")(p)$ for the unique observable result determined by the plan
constructor:

- `Den(MapPlan(cfg, op, src, dst))` is the buffer `dst` whose element at index `i` is
  `Apply(op, src[i])`;
- `Den(ReducePlan(cfg, mu, src, out))` is the scalar result in `out[0]` obtained by
  folding `src` with the law `mu`;
- `Den(ScanPlan(cfg, mu, src, dst))` is the inclusive prefix-result buffer `dst` whose
  element at index `i` equals the reduction of `src[0 .. i]` under `mu`;
- `Den(MapReducePlan(cfg, op, mu, src, out))` is
  `Den(ReducePlan(cfg, mu, upright("MapTmp")(op, src), out))`, where
  `MapTmp(op, src)` is the logical mapped sequence produced by applying `op` pointwise to
  `src`.

*Definition (Plan Well-Formedness).*
Write $upright("PlanWF")(p)$ iff:

- `threads > 0`;
- `chunk > 0` whenever chunked parallel execution is requested;
- empty-input `map` and `scan` plans are admitted only when their shape obligations still
  determine a unique empty result buffer;
- empty-input `reduce` plans are admitted only when `IdentityId` resolves to an audited
  identity element for the carried `MonoidLaw`, otherwise they are rejected before
  lowering;
- every referenced buffer has explicit scalar kind, length, access mode, and layout
  witness;
- every `OutRef` has explicit scalar kind, length, and layout witness;
- every operator id resolves to a trusted registered kernel descriptor;
- every monoid law descriptor carries an explicit law class, operator id, identity id,
  and associativity or deterministic-tree witness identifier;
- `ShapeOK(p)` holds.

*Definition (Reduction-Law Admissibility).*
Write $upright("LawOK")(mu, tau)$ iff:

- if `ClassOf(mu) = StrictAssoc`, then `AssocWitness(mu)` denotes a strict associative law
  over element type `tau`; and
- if `ClassOf(mu) = DeterministicTree`, then `tau in {Float, Double}` and
  `AssocWitness(mu)` denotes a fixed reduction-tree witness for the normalized descriptor.

Floating-point `reduce` and `scan` plans are admissible only through
`DeterministicTree`; the specification does not treat IEEE 754 addition or multiplication
as unrestricted algebraic monoids.

*Definition (Floating-Point Conformance Profile).*
Write $upright("FPProfile")(t)$ for the target-local floating-point environment declared by
target `t`, including rounding mode, contraction policy, NaN and infinity handling,
subnormal handling, and any other condition required to interpret a `DeterministicTree`
result.

== ABI Layout Isomorphism

Zero-copy borrowing or representation-preserving transfer is permitted only when MoonBit
and C layouts are isomorphic at the boundary.

*Definition (Boundary View Layout).*
For a layout-bearing buffer view on the active backend target, define the boundary view
record:

#figure(
  $
    text("lv_view") ::= & "{" \
                       & quad text("addr") ":" text("UIntPtr") "," \
                       & quad text("len") ":" text("UInt64") "," \
                       & quad text("kind") ":" text("UInt32") "," \
                       & quad text("mode") ":" text("UInt32") "," \
                       & quad text("stride") ":" text("UInt64") \
                       & "}"
  $,
  caption: [Canonical boundary view.],
)

The canonical boundary ABI is not inferred from an unspecified machine word `w`; it is
selected by an audited target profile `ABIProfile(t)`.

*Definition (Boundary ABI Profile).*
`ABIProfile(t)` must declare the unique width, alignment, and endian contract used by
boundary records on target `t`, including the mapping of `UIntPtr`, `UInt64`, and
`UInt32`.

with required layout equations under `ABIProfile(t)`:

$
  upright("sizeof")(upright("lv_view")) = upright("LVSize")(upright("ABIProfile")(t))
  and upright("alignof")(upright("lv_view")) = upright("LVAlign")(upright("ABIProfile")(t))
$

$
  upright("offset")(upright("addr")) = 0
  and upright("offset")(upright("len")) = upright("OffLen")(upright("ABIProfile")(t))
  and upright("offset")(upright("kind")) = upright("OffKind")(upright("ABIProfile")(t))
$

$
  upright("offset")(upright("mode")) = upright("OffMode")(upright("ABIProfile")(t))
  and upright("offset")(upright("stride")) = upright("OffStride")(upright("ABIProfile")(t))
$

*Definition (Layout Record).*
For a scalar or buffer element type `tau`, define:

$
  upright("Layout")(tau) = (upright("size")(tau), upright("align")(tau), upright("stride")(tau), upright("endian")(tau))
$

*Definition (Layout Isomorphism).*
Write $upright("Iso")(tau_M, tau_C)$ iff:

$
  upright("Layout")(tau_M) = upright("Layout")(tau_C)
$

and both sides agree on scalar interpretation, element width, and contiguous traversal
semantics.

*Constraint (Boundary Layout Gate).*

$
  upright("Iso")(tau_M, tau_C)
  /
  upright("LayoutOK")(tau_M, tau_C)
$

If $upright("LayoutOK")$ fails, the implementation must either copy into a conforming
layout or reject the request. It may not silently reinterpret one layout as another.

`LayoutOK` additionally requires that the active target admit one audited `ABIProfile(t)`
for the path that carries the view. A realization may not substitute a different
record layout based on accidental host ABI compatibility.

== Linear Ownership State Machine

The boundary contract is a small transition system over ownership-resource contexts.

*Ownership states.*
`Own_M(b)`, `Borrow_MR(b)`, `Borrow_C(b)`, `Own_C(b)`, and `Returned_M(b)` are the only
admissible ownership states for a buffer identity `b`.

`Returned_M(b)` is an observable return-complete intermediate state: C-visible authority
has been relinquished, but MoonBit mutable authority is not restored until the rehydration
step succeeds.

*Transition rules.*

#figure(
  $
    frac(
      Gamma tack upright("Own_M")(b) and upright("LayoutOK")(tau_M, tau_C) and upright("Live")(b) and upright("ReadOnly")(q),
      Gamma -> (Gamma - {upright("Own_M")(b)}) union {upright("Borrow_MR")(b), upright("Borrow_C")(b)}
    ) quad text("(Borrow-Step)") \
    frac(
      Gamma tack upright("Own_M")(b) and upright("LayoutOK")(tau_M, tau_C) and upright("Exclusive")(b) and upright("TransferOK")(q),
      Gamma -> (Gamma - {upright("Own_M")(b)}) union {upright("Own_C")(b)}
    ) quad text("(Transfer-Step)") \
    frac(
      Gamma tack upright("Own_C")(b) and upright("Received")(b) and upright("Rebind")(b),
      Gamma -> (Gamma - {upright("Own_C")(b)}) union {upright("Returned_M")(b)}
    ) quad text("(Return-Step)") \
    frac(
      Gamma tack upright("Returned_M")(b) and upright("RehydrateOK")(b),
      Gamma -> (Gamma - {upright("Returned_M")(b)}) union {upright("Own_M")(b)}
    ) quad text("(Rehydrate-Step)") \
    frac(
      Gamma tack upright("Borrow_MR")(b) and upright("Borrow_C")(b) and upright("BorrowDone")(b),
      Gamma -> (Gamma - {upright("Borrow_MR")(b), upright("Borrow_C")(b)}) union {upright("Own_M")(b)}
    ) quad text("(Discharge-Step)")
  $,
  caption: [Linear ownership transitions.],
)

*Linearity condition.*
No reachable context may contain both `Own_M(b)` and `Own_C(b)` for the same `b`, and any
active `Borrow_C(b)` blocks MoonBit-side mutation and free until the borrow token is discharged by `Discharge-Step`.

== Boundary Payloads

The FFI boundary transports plans and layout-checked views, not arbitrary object graphs.

*Payload skeleton.*

```c
typedef struct {
  PlanTag plan_tag;
  CfgBits cfg_bits;
  ViewVec views;
  OpBits op_bits;
  LawBits law_bits;
} Payload;
```

where each view entry carries:

- buffer identity or boundary view handle;
- scalar-kind tag;
- length;
- access mode;
- layout witness or layout class tag;
- ownership mode (`Borrow` or `Transfer`).

*Boundary admissibility.*
`Adm(t, q)` holds only when:

- the payload tag belongs to the target-specific payload grammar;
- every carried view satisfies `LayoutOK`;
- every requested ownership transition is legal under the linear state machine;
- every operator or monoid id resolves to a target-admitted trusted descriptor or law for `t`.

== Wrapper Parsing and Descriptor Formation

The C wrapper or JS/N-API boundary is the interpreter from payload syntax to runtime
descriptors.

*Runtime descriptor.*

```c
typedef struct {
  PlanTag plan_tag;
  CfgNorm cfg_norm;
  ChunkPolicy chunk_policy;
  BufSliceVec buf_slices;
  KernelDesc kernel_desc;
  LawHandle law_handle;
} Descriptor;
```

*Kernel descriptor and registry.*

```c
typedef struct {
  KernelId kernel_id;
  FnPtr fn_ptr;
  PurityWitness purity_witness;
  FootprintWitness footprint_witness;
  LayoutContract layout_contract;
  ArityMeta arity_meta;
  LawMeta law_meta;
  TargetMeta target_meta;
} KernelDesc;
```

`KernelRegistry(t)` is a static audited mapping from `KernelId` to `KernelDesc` for target
`t`. `KernelId` is the only kernel-level identifier admissible in plan payloads; `FnPtr`
is implementation-only and never crosses the MoonBit plan boundary.

*Parsing relation.*

Write $upright("ParseCore")(t, q, p, c, V, k, mu)$ iff:

- `DecodePlan(q) = p`;
- `NormCfg(q) = c`;
- `NormViews(q) = V`;
- `ResolveKernel(KernelRegistry(t), q) = k`; and
- `ResolveLaw(q) = mu`.

Write $upright("ViewsOK")(V)$ iff every `v in V` satisfies both `LayoutOK(v)` and
`OwnerOK(v)`.

Write $upright("ParseReady")(t, p, V, k, mu)$ iff `KernelOK(k, p, V, mu, t)`.

#figure(
  $
    frac(
      upright("ParseCore")(t, q, p, c, V, k, mu) and upright("ViewsOK")(V) and upright("ParseReady")(t, p, V, k, mu),
      upright("parse")(t, q) mapsto upright("Descriptor")(p, c, upright("ChunkPolicy")(c), V, k, mu)
    )
  $,
  caption: [Wrapper parsing relation.],
)

*Descriptor fidelity rule.*
The produced descriptor must preserve:

- the constructor class of the plan;
- the scalar-kind and layout class of each carried buffer;
- the ownership mode attached to each boundary view;
- the `KernelId` selected by the plan and the audited descriptor resolved from the trusted registry;
- the shape obligations required by the plan constructor; and
- the denotation-defining choice of scan prefix semantics and map-reduce lowering.

== Fork-Join Operational Semantics

We define a labelled small-step semantics over configurations `Conf(C, H, S)`, where `H` is
the host heap and `S` is the worker-local store. Part III refines this abstract machine
with explicit fail-closed error publication obligations for physical C/OpenMP realizations.

*Worker syntax.*

#figure(
  $
    text("Worker") ::= & text("Read") "(" text("Addr") ")" \
                     |   & text("Write") "(" text("Addr") "," text("Val") ")" \
                     |   & text("MapStep") "(" text("Op") "," text("Addr") "," text("Addr") ")" \
                     |   & text("ScanStep") "(" text("Law") "," text("Addr") "," text("Addr") "," text("State") ")" \
                     |   & text("Seq") "(" text("Worker") "," text("Worker") ")" \
                     |   & text("Done") "(" text("Val") ")"
  $,
  caption: [Worker syntax.],
)

*Read rule.*

#figure(
  $
    frac(
      H(a) = v,
      upright("Conf")(upright("Read")(a), H, S) -> upright("Conf")(upright("Done")(v), H, S)
    )
  $,
  caption: [Read step.],
)

*Write rule.*

#figure(
  $
    frac(
      upright("Writable")(a, S),
      upright("Conf")(upright("Write")(a, v), H, S) -> upright("Conf")(upright("Done")(v), H[a := v], S)
    )
  $,
  caption: [Write step.],
)

*Map rule.*

#figure(
  $
    frac(
      H(a_s) = x and upright("Writable")(a_d, S) and upright("Apply")(op, x) = y,
      upright("Conf")(upright("MapStep")(op, a_s, a_d), H, S) -> upright("Conf")(upright("Done")(y), H[a_d := y], S)
    )
  $,
  caption: [Map step.],
)

*Scan rule.*

#figure(
  $
    frac(
      H(a_s) = x and upright("Writable")(a_d, S) and upright("Combine")(mu, s, x) = s',
      upright("Conf")(upright("ScanStep")(mu, a_s, a_d, s), H, S) -> upright("Conf")(upright("Done")(s'), H[a_d := s'], S)
    )
  $,
  caption: [Scan step.],
)

*Sequence rules.*

#figure(
  $
    frac(
      upright("Conf")(C_1, H, S) -> upright("Conf")(C_1', H', S'),
      upright("Conf")(upright("Seq")(C_1, C_2), H, S) -> upright("Conf")(upright("Seq")(C_1', C_2), H', S')
    ) \
    frac(
      upright("Conf")(C_2, H, S) -> upright("Conf")(C_2', H', S'),
      upright("Conf")(upright("Seq")(upright("Done")(v), C_2), H, S) -> upright("Conf")(C_2', H', S')
    )
  $,
  caption: [Sequence steps.],
)

*Footprint contract.*
`R(C)` is the set of addresses read by one step of `C`, `W(C)` is the set of addresses
written by one step of `C`, and `FP(C) = R(C) union W(C)`.

*Descriptor metadata region.*
For every parsed descriptor `d`, define `MetaOf(d)` as the read-only metadata region that
stores the normalized runtime configuration, operator handle and parameters, law handle,
and any per-plan constants required by spawned workers.

*Chunk partition contract.*
`Chunks(n, k) = [I_0, ..., I_(k-1)]` only when the intervals cover `[0, n)` and are pairwise
disjoint.

*Worker instantiation contract.*
If worker `C_i` is instantiated for slice `I_i`, then `FP(C_i)` must stay within
`AddrOf(I_i) union MetaOf(d)`, and `MetaOf(d)` must remain read-only.

*Fork and join rules.*

#figure(
  $
    frac(
      upright("Chunks")(n, k) = [I_0, dots.c, I_(k-1)] and forall i. upright("Spawn")(d, I_i) = C_i,
      upright("Conf")(upright("Fork")(d), H, S) -> upright("Conf")(upright("Par")([C_0, dots.c, C_(k-1)]), H, S)
    ) \
    frac(
      forall i. C_i = upright("Done")(y_i),
      upright("Conf")(upright("Par")([C_0, dots.c, C_(k-1)]), H, S) -> upright("Conf")(upright("Done")(upright("Fold")(mu, upright("TreeOf")(d), [y_0, dots.c, y_(k-1)])), H, S)
    )
  $,
  caption: [Fork and join steps.],
)

*Scan and map-reduce realization rule.*
If `plan_tag(d) = ScanPlan`, then `Spawn(d, I_i)` must emit workers whose left-to-right
join writes the inclusive prefix result required by `Den(ScanPlan(...))`. If
`plan_tag(d) = MapReducePlan`, then descriptor normalization must preserve the logical
lowering to map-then-reduce used by `Den(MapReducePlan(...))`; implementations may fuse
the physical execution only when the observable result remains the same as that denotation.

*Floating-point combine rule.*
If `ClassOf(mu) = DeterministicTree`, then `TreeOf(d)` is part of descriptor normalization
and uniquely determines the split-combine order. Reordering by worker scheduling does not
change the combine tree selected by `d`. This rule guarantees a stable result for repeated
executions under one target-local `FPProfile(t)`; cross-target equality is required only
when the compared targets declare compatible audited floating-point profiles.

*Parallel step side condition.*
If `Conf(C_i, H, S) -> Conf(C_i', H', S')`, then the lifted step on
`Par([C_0, ..., C_i, ..., C_(k-1)])` is admissible only when
`W(C_i) ∩ FP(C_j) = emptyset` for every `j != i`.

== JS ArrayBuffer Boundary Semantics

The JavaScript boundary is modeled as a target-specific transition system on host views.

*JS view syntax.*

#figure(
  $
    text("JSView") ::= & "(" text("ArrayBufferKind") "," text("Offset") "," text("Len") "," text("ScalarKind") "," text("AccessMode") "," text("Share") ")"
  $,
  caption: [JavaScript boundary views.],
)

*Boundary rules.*

#figure(
  $
    frac(
      upright("Kind")(v) = upright("SharedArrayBuffer") and upright("Access")(v) = upright("ReadOnly") and upright("LayoutOK")(v) and upright("AtomicOK")(v),
      (upright("Own_M")(b), v) -> (upright("Borrow_MR")(b) * upright("Borrow_C")(b), v)
    ) \
    frac(
      upright("Kind")(v) = upright("ArrayBuffer") and upright("CopyBytes")(b) = b' and upright("CopyOwner")(b') = upright("HostRuntime"),
      (upright("Own_M")(b), v) -> (upright("Own_M")(b) * upright("Own_C")(b'), v)
    ) \
    frac(
      upright("TransferOK")(v) and upright("Tombstone")(v),
      (upright("Own_M")(b), v) -> (upright("Own_C")(b), v)
    )
  $,
  caption: [Borrow, copy, and transfer at the JS boundary.],
)

*Locking side condition.*
Every derivation of the shared-borrow rule carries a host-side lock obligation: no write on
the shared region is admissible unless the matching atomic discipline is present in `Share`.

*Shared snapshot obligation.*
An admitted `SharedArrayBuffer` borrow is interpreted against one logical snapshot of the
read-only input region. The implementation may realize that snapshot by copying, freezing,
or an observationally equivalent mechanism, but the accepted execution must preserve
`Den(p)` for the snapped input rather than for later host-side writes.

*JS lifecycle obligation.*
For the copy rule, the host runtime owns `b'` and must dispose it exactly once by explicit
release or finalizer. For the transfer rule, the host object becomes a tombstone
immediately after transfer admission; explicit return has priority over finalizer cleanup,
and finalizer cleanup has priority over leak-on-fault behavior. If runtime admission or
worker execution fails closed after transfer, the target must publish one deterministic
cleanup path for the still-owned C-visible buffer.

== Separation and Data-Race Freedom

*Spatial separation predicate.*

$
  upright("SepChunks")(b, [I_0, dots.c, I_(k-1)]) = forall i != j. upright("AddrOf")(I_i) inter upright("AddrOf")(I_j) = emptyset
$

*Parallel admissibility.*

$
  upright("ParOK")([C_0, dots.c, C_(k-1)]) = forall i != j. upright("W")(C_i) inter upright("FP")(C_j) = emptyset
$

*Theorem (Data-Race Freedom).*
If:

1. `KernelSafe(d)` holds, meaning the resolved audited kernel descriptor satisfies
   `PurityWitness`, `FootprintWitness`, `LayoutContract`, and `LawMeta`,
2. `SepChunks(b, [I_0, ..., I_(k-1)])`,
3. each worker `C_i` is spawned from `I_i`,
4. `FP(C_i) subset.eq AddrOf(I_i) union MetaOf(d)` for every `i`, and
5. `MetaOf(d)` is read-only,

then every reachable configuration `Conf(Par([C_0, ..., C_(k-1)]), H, S)` satisfies
`ParOK([C_0, ..., C_(k-1)])`.

*Proof.*
By induction on the length of the reduction derivation. The base case follows from the
chunk-spawn invariant and the definition of `SepChunks`. Premise (1) closes the theorem
under the audited-kernel admissibility assumptions needed to derive worker footprints from
plan data alone. For the inductive step, only one worker `C_i` can take a small step. By
premise (4), any write of `C_i` lies in `AddrOf(I_i)`. For every `j != i`, premise (4)
gives `FP(C_j) subset.eq AddrOf(I_j) union MetaOf(d)`. Premise (2) makes `AddrOf(I_i)`
disjoint from `AddrOf(I_j)`, and premise (5) forbids writes into `MetaOf(d)`. Therefore
`W(C_i) inter FP(C_j) = emptyset` is preserved for all `j != i`, so the parallel
configuration remains `ParOK`.

*Corollary (Ownership Safety).*
If `Borrow_C(b)` is active, MoonBit cannot derive a step that frees or mutates `b`; if
`Own_M(b) -> Own_C(b)` has fired, MoonBit cannot derive mutable authority for `b` again
without an explicit `Return-Step` followed by `Rehydrate-Step`; if `Borrow_MR(b) *
Borrow_C(b)` is active, `Own_M(b)` is restored only by `Discharge-Step`.

= Part II: Realization and Conformance

== Native Realization

The native realization is:

`MoonBit facade -> MoonBit C FFI -> C wrapper -> runtime descriptor -> C runtime`

A conforming native realization must:

- lower only plan ADT values admitted by Part I;
- preserve one audited `ABIProfile(t)` for each admitted boundary path, or perform
  explicit copying when layout is not isomorphic;
- implement borrow and transfer edges according to the linear state machine;
- schedule writable chunks only under the separation contract of Part I.

== JavaScript Realization

The JavaScript realization is:

`MoonBit facade -> MoonBit JS FFI -> JS wrapper -> N-API addon -> runtime descriptor -> C runtime`

A conforming JavaScript realization must:

- lower typed-array-compatible views into payload views with explicit element-kind tags;
- reject host objects that do not satisfy layout and ownership obligations;
- preserve the same plan denotation and split-combine contract as the native realization,
  and require stronger cross-target equality only when both sides declare compatible
  `FPProfile`;
- realize admitted `SharedArrayBuffer` borrows as logical snapshots for denotation
  purposes;
- define owner, tombstone, finalizer, and explicit-return behavior for copy and transfer
  paths before runtime execution starts;
- enforce borrow or transfer discipline before runtime execution starts.

== Facade Obligations

A conforming facade must:

- expose only pure plan constructors and explicit execution entry points;
- refuse to encode arbitrary function-value environments or arbitrary host functions into plans;
- attach explicit ownership mode and access mode to every exported boundary view;
- surface capability queries that are extensionally equal to actual target support.

== Runtime Obligations

A conforming runtime must:

- interpret descriptors only through the constructor classes defined in Part I;
- reject any descriptor whose chunk schedule fails separation or side-condition checks;
- preserve the ownership mode attached to each carried view;
- lift failures into explicit status classes rather than partial success;
- prohibit exception escape, panic propagation, or stack unwinding across the FFI boundary;
- implement deterministic layout fallback or rejection for non-isomorphic views before worker execution starts.

== Unsupported Surface

The following are outside the version-1 contract:

- arbitrary MoonBit function-value execution on foreign worker threads;
- arbitrary JavaScript host-function execution inside native worker execution;
- implicit layout reinterpretation across non-isomorphic ABI records or arrays;
- implicit ownership transfer without a boundary state transition;
- chunk schedules that cannot be justified by separation and split-combine laws.

== Conformance

An implementation may claim conformance only if:

- its MoonBit-facing API constructs only the plan ADT admitted by Part I;
- its boundary payloads preserve explicit layout and ownership witnesses;
- its wrappers satisfy parsing fidelity and ownership fidelity;
- its runtime satisfies chunk orthogonality and split-combine soundness;
- invalid, non-isomorphic, or lifetime-unsafe requests fail closed before execution.

== Conformance Transfer

*Faithful realization.*
An implementation is faithful only if:

- every accepted payload is the lowering of a well-formed plan;
- every borrow or transfer edge follows the linear ownership state machine;
- every writable chunk schedule satisfies `SepChunks`;
- every reduction or scan combine path is justified by a valid monoid descriptor.

*Conformance rule.*
If a faithful implementation accepts a plan `p`, then the observable result and ownership
trace of executing `p` must stay within Part I. If it rejects `p`, that rejection must be a
spec-valid fail-closed outcome. For floating-point `reduce` and `scan`, "the observable
result" means stable repeated results under one admitted target profile, and cross-target
equality only under explicitly compatible audited floating-point profiles.

== Validation Scenarios

1. Submit a plan whose source and destination layouts are not isomorphic.
   Expected result: explicit copy into a conforming layout, or fail-closed rejection.
2. Submit a read-only borrow plan and attempt MoonBit-side mutation before borrow
   discharge.
   Expected result: mutation is rejected or blocked by the borrow discipline.
3. Submit a writable chunk schedule with overlapping intervals.
   Expected result: descriptor formation or runtime admission fails before execution.
4. Submit a reduce or scan plan with an operator lacking a valid monoid descriptor.
   Expected result: the plan is rejected before fork-join execution.
5. Submit a transfer plan and attempt MoonBit-side free through an old alias.
   Expected result: mutable alias permission is absent; the operation is rejected.
6. Execute equivalent floating-point reduce plans on native and JavaScript targets with
   layout-compatible views but incompatible floating-point profiles.
   Expected result: each target is internally deterministic, but cross-target equality is
   not claimed.
7. Execute equivalent floating-point reduce plans on targets that declare compatible
   floating-point profiles.
   Expected result: both targets preserve the same declared observable result and ownership
   discipline.
8. Submit a transfer-return-reuse plan and attempt reuse before `Rehydrate-Step`.
   Expected result: reuse is rejected until rehydration succeeds.
9. Submit a JS copy or transfer plan and trigger explicit return, finalizer cleanup, and
   fail-closed runtime admission on separate runs.
   Expected result: the documented lifecycle priority and single-disposal obligations hold.

== Closure Checklist

The specification is not closed unless all of the following hold:

1. Every exported execution request is representable by the plan ADT.
2. Every boundary view carries explicit layout and ownership witnesses.
3. Every zero-copy path satisfies layout isomorphism.
4. Every borrow path freezes MoonBit mutation until discharge.
5. Every transfer path consumes MoonBit mutable authority and restores it only through
   explicit return plus rehydration.
6. Every writable chunk schedule is justified by separation.
7. Every reduction or scan combine path is justified by a valid monoid law.
8. No exception, panic, or abort path escapes across the FFI boundary.
9. Every zero-copy admission path discharges byte-level layout and alignment checks.
10. Every JS copy and transfer path has one closed cleanup story, including finalizer and
    fail-closed cases.
11. Every witness obligation maps to an auditable artifact format.
12. Every invalid input vector fails by explicit status rather than crash or undefined behavior.
13. Every referenced guarantee is stated in the document.
