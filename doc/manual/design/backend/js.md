# backend/js design

## Design goal

The specification describes a second realization path: MoonBit code compiled
to JavaScript that passes typed array buffers to a Node.js addon, which calls
the same C runtime as the native backend. `backend/js` reserves the package for
that path and fixes its identity, so that the rest of the module can already
name the JavaScript target in policies, capability tables and submissions.

## Constraints

- The package must build on every target, including `js`, and must not
  declare foreign functions that have no implementation behind them.
- It must name the JavaScript target with the same `BackendTarget` value the
  rest of the module uses, so that policies and submissions can refer to it.

## Main design decisions

### A package before a backend

Declaring the package now keeps the module layout of the specification
(`backend/native` and `backend/js` side by side) and lets code depend on
`@js.backend_target()` rather than on a constructor of `shared`. When the
backend is implemented, its foreign declarations and wrappers go here without a
new import path.

### No foreign declarations yet

The addon in `js/` exports only `runtimeName` and does not link the C runtime,
so there is nothing to declare. Declaring functions with no implementation
would compile but fail at run time, which is worse than not offering them.

## Mathematical background

The package computes nothing. The only structure it takes part in is the
backend sum type

$$
B = \{\, \mathrm{Native}, \mathrm{JavaScript} \,\},
$$

with each backend package providing the constant
$\texttt{backend\_target} \in B$ that names it. For the JavaScript package this
constant is $\mathrm{JavaScript}$, and the v1 policy subset $P_1$ described on
the [shared design](../shared.md) page excludes it, so every policy or
submission that names this backend is rejected before reaching any runtime.

## Correctness / invariants

- `backend_target()` returns `JavaScript`, `default_plan_kind()` returns `Map`
  and `package_name()` returns `"backend/js"`; the package has no state.
- The package builds on every target, including `js`.

## Alternatives rejected

- **Omitting the package until the backend exists.** Downstream code would
  then have no stable place to refer to the JavaScript backend.
- **A stub that runs kernels in MoonBit on the JavaScript target.** It would
  bypass the C runtime and the ownership rules of the specification, giving
  results that the real backend might not reproduce.

## Boundaries

The package does not execute plans or workflows, declare foreign functions,
load the Node.js addon, or move data across the JavaScript boundary.
