# MoonBit Parallel FFI Spec 复审报告

## 结论

当前版本虽然继续修订，但审计结论仍然不能放松。上一版指出的问题里，确有部分条款已经被补入正文，例如 payload / descriptor 的构造子拆分、`Borrow` 的只读约束、`scan` 的 `JoinState`、以及 JS snapshot 的不可观察复制。但这些修订尚未形成一次性闭合的整体结果，反而暴露出更明显的前后层级不一致。

本轮结论是：`不通过，本轮修订不得以局部补丁形式收尾，必须一次性完成整体闭合修复后再复审`。

需要明确指出，当前遗留问题已经不是“文档还可继续润色”这一级别，而是会直接破坏以下能力：

- 第三方独立实现时的唯一解释性；
- conformance claim 的可重复审计性；
- fail-closed 行为的统一判定；
- semantic core 作为唯一规范源的权威性。

因此，不接受“先修一部分、其余留到后续版本”“实现里先约定俗成补齐”“由 reviewer 自行理解黑盒谓词”这类处理方式。下一轮提交必须以一次性闭合为目标，把 semantic core、payload/descriptor、boundary result carrier、admission 谓词和 validation mapping 全部同步修完。任何只修单点、不补全全链路约束的版本，均应视为未通过复审。

## Findings

### F1. semantic core 与 realization/conformance 段落对访问与所有权合同的表述仍不一致

- 严重级别：高
- 证据：
  - `ShapeOK` 仍只写了 destination writable，没有把 source readable、`OutRef` result-only 写进 Part I 的核心定义。见 [docs/moonbit-parallel-spec-en.typ](/Users/kcn/Desktop/repos/MoonVibe/luna_thread/docs/moonbit-parallel-spec-en.typ:160)、[docs/moonbit-parallel-spec-en.typ](/Users/kcn/Desktop/repos/MoonVibe/luna_thread/docs/moonbit-parallel-spec-en.typ:163)、[docs/moonbit-parallel-spec-en.typ](/Users/kcn/Desktop/repos/MoonVibe/luna_thread/docs/moonbit-parallel-spec-en.typ:168)。
  - `PlanWF` 对 `OutRef` 只要求 kind/len/layout witness，没有说 result-only。见 [docs/moonbit-parallel-spec-en.typ](/Users/kcn/Desktop/repos/MoonVibe/luna_thread/docs/moonbit-parallel-spec-en.typ:187)、[docs/moonbit-parallel-spec-en.typ](/Users/kcn/Desktop/repos/MoonVibe/luna_thread/docs/moonbit-parallel-spec-en.typ:199)。
  - 但后文又明确声明 version 1 的 `Borrow` 只代表只读 borrow，writable output 必须走 transfer。见 [docs/moonbit-parallel-spec-en.typ](/Users/kcn/Desktop/repos/MoonVibe/luna_thread/docs/moonbit-parallel-spec-en.typ:347)、[docs/moonbit-parallel-spec-en.typ](/Users/kcn/Desktop/repos/MoonVibe/luna_thread/docs/moonbit-parallel-spec-en.typ:376)、[docs/moonbit-parallel-spec-en.typ](/Users/kcn/Desktop/repos/MoonVibe/luna_thread/docs/moonbit-parallel-spec-en.typ:788)、[docs/moonbit-parallel-spec-en.typ](/Users/kcn/Desktop/repos/MoonVibe/luna_thread/docs/moonbit-parallel-spec-en.typ:797)。
  - validation matrix 也已经要求 “any view lowered with ownership mode `Borrow` is `ReadOnly`”。见 [docs/moonbit-parallel-spec-en.typ](/Users/kcn/Desktop/repos/MoonVibe/luna_thread/docs/moonbit-parallel-spec-en.typ:1152)。
- 问题分析：
  - Part II/III 已经把访问与所有权合同说得更严格，但 Part I 的核心良构性定义还停留在旧表述。
  - 这会导致读者无法判断“只读 borrow / result-only outref / source readable”到底是 semantic core 的规范性要求，还是 realization 层后来附加的工程限制。
- 影响：
  - 第三方实现者可能在 facade 层接受一个通过 `PlanWF` / `ShapeOK` 的 plan，却在 wrapper/runtime 层再被新的 contract 拒绝。
  - 这削弱了 Part I 作为 authoritative semantic core 的地位。
- 建议：
  - 把以下约束前移到 Part I，并写进 `ShapeOK` 或 `PlanWF`：
    - source 必须 readable；
    - `OutRef` 是 result-only；
    - version 1 的 `Borrow` 仅适用于 `ReadOnly` view。
  - 保证 Part II/III 只是在实现层“出清”这些要求，而不是重新定义它们。

### F2. 构造子拆分已开始，但通用边界结果类型仍引用不存在的 `Payload`

- 严重级别：高
- 证据：
  - 文档已经把 payload 按构造子拆成 `Payload_Map`、`Payload_Reduce`、`Payload_Scan`、`Payload_MapReduce`。见 [docs/moonbit-parallel-spec-en.typ](/Users/kcn/Desktop/repos/MoonVibe/luna_thread/docs/moonbit-parallel-spec-en.typ:354)、[docs/moonbit-parallel-spec-en.typ](/Users/kcn/Desktop/repos/MoonVibe/luna_thread/docs/moonbit-parallel-spec-en.typ:357)。
  - descriptor 也按构造子拆成 `Descriptor_Map`、`Descriptor_Reduce`、`Descriptor_Scan`、`Descriptor_MapReduce`。见 [docs/moonbit-parallel-spec-en.typ](/Users/kcn/Desktop/repos/MoonVibe/luna_thread/docs/moonbit-parallel-spec-en.typ:393)、[docs/moonbit-parallel-spec-en.typ](/Users/kcn/Desktop/repos/MoonVibe/luna_thread/docs/moonbit-parallel-spec-en.typ:396)。
  - 但 Part III 的 boundary result carrier 仍写成：
    `typedef struct { Status status; Payload payload; } FFIResult_Payload;`
    其中 `Payload` 已不再有定义。见 [docs/moonbit-parallel-spec-en.typ](/Users/kcn/Desktop/repos/MoonVibe/luna_thread/docs/moonbit-parallel-spec-en.typ:932)、[docs/moonbit-parallel-spec-en.typ](/Users/kcn/Desktop/repos/MoonVibe/luna_thread/docs/moonbit-parallel-spec-en.typ:937)、[docs/moonbit-parallel-spec-en.typ](/Users/kcn/Desktop/repos/MoonVibe/luna_thread/docs/moonbit-parallel-spec-en.typ:939)。
- 问题分析：
  - 这是一个明确的类型骨架不一致：文档前面已经从“单一 payload”切换到“constructor-specific payload”，但后面仍保留旧的通用结果封装。
  - 如果这里想表达 tagged union，需要显式定义；如果只是示意，也需要说清是“observationally equivalent sum carrier”。
- 影响：
  - 实现者无法从 spec 唯一确定 FFI 边界上的结果载体。
  - 这会直接影响 ABI-safe envelope 的可实现性与可审计性。
- 建议：
  - 明确定义一个总和类型，例如 `Payload_Result = Payload_Map | Payload_Reduce | Payload_Scan | Payload_MapReduce`；或
  - 将 `FFIResult_Payload` 改为构造子特化的 envelope，并说明 target-facing API 如何统一暴露。

### F3. 若干关键 admission / correctness 谓词仍是黑盒，第三方无法独立判定符合性

- 严重级别：中高
- 证据：
  - `OwnerOK(v)` 直接用于 `ViewsOK(V)`，但正文没有定义。见 [docs/moonbit-parallel-spec-en.typ](/Users/kcn/Desktop/repos/MoonVibe/luna_thread/docs/moonbit-parallel-spec-en.typ:442)。
  - `KernelOK(k, p, V, mu, t)` 用于 `ParseReady...`，但正文没有展开其判定条件。见 [docs/moonbit-parallel-spec-en.typ](/Users/kcn/Desktop/repos/MoonVibe/luna_thread/docs/moonbit-parallel-spec-en.typ:445)、[docs/moonbit-parallel-spec-en.typ](/Users/kcn/Desktop/repos/MoonVibe/luna_thread/docs/moonbit-parallel-spec-en.typ:447)。
  - `TransferOK(q)`、`TransferOK(v)` 分别用于线性状态机与 JS transfer 规则，也未给定义。见 [docs/moonbit-parallel-spec-en.typ](/Users/kcn/Desktop/repos/MoonVibe/luna_thread/docs/moonbit-parallel-spec-en.typ:324)、[docs/moonbit-parallel-spec-en.typ](/Users/kcn/Desktop/repos/MoonVibe/luna_thread/docs/moonbit-parallel-spec-en.typ:673)。
  - `JoinScan(d, ...)`、`MapResult(d)`、`ScanResult(d, sigma)` 已经进入 join 规则核心，但也都是未解释的元函数。见 [docs/moonbit-parallel-spec-en.typ](/Users/kcn/Desktop/repos/MoonVibe/luna_thread/docs/moonbit-parallel-spec-en.typ:605)、[docs/moonbit-parallel-spec-en.typ](/Users/kcn/Desktop/repos/MoonVibe/luna_thread/docs/moonbit-parallel-spec-en.typ:612)、[docs/moonbit-parallel-spec-en.typ](/Users/kcn/Desktop/repos/MoonVibe/luna_thread/docs/moonbit-parallel-spec-en.typ:621)。
- 问题分析：
  - 抽象谓词本身不是问题，但这些谓词已经位于 admission、parsing、join correctness 的关键闭环上。
  - 当前 spec 对它们的约束仍主要依赖读者从上下文反推，缺少“足以让第三方独立判断 yes/no”的最小定义。
- 影响：
  - 不同实现者或审核方会把 `OwnerOK`、`KernelOK`、`TransferOK` 的判定口径各自补完。
  - 这会让“faithful realization”与 validation matrix 的结果难以复现。
- 建议：
  - 至少给出这些谓词的最小判定条目，而不一定要求完全形式化。
  - 建议优先补：
    - `OwnerOK(v)` 的资源与 alias 条件；
    - `KernelOK(...)` 对 `ArityMeta` / `LawMeta` / access mode 的检查项；
    - `TransferOK(...)` 的 authority、liveness、tombstone、rebind 前提；
    - `JoinScan` / `MapResult` / `ScanResult` 与 `Den(p)` 的对应关系。

## 审计意见

本轮审计不接受继续“边修边看”的推进方式。当前剩余问题已经明确收敛到 3 条主链路：

1. Part I 与 Part II/III 对同一访问/所有权规则的规范性位置不一致。
2. constructor-specific payload/descriptor 已经成形，但边界结果载体仍停留在旧模型。
3. admission / correctness 的关键谓词仍然太抽象，不足以支撑第三方独立判定符合性。

这 3 条不是彼此独立的小问题，而是同一件事的三个表现：规范还没有形成可执行、可审计、可外包实现的单一合同。只修其中一条，另外两条仍会把整个规范重新拉回“实现自补”“审核自补”“口径漂移”的状态。

因此，本报告的管理性结论必须写死：

- 不接受分批修复。
- 不接受实现侧补解释替代规范修订。
- 不接受把关键判定留给 reviewer 或 implementer 自由裁量。
- 不接受以“下一轮再统一”为理由放行当前版本。

下一轮必须一次性完成以下闭合动作：

1. 把访问/所有权约束前移并统一到 semantic core。
2. 把所有 payload / descriptor / result carrier 改成同一种 constructor-specific 模型。
3. 把 `OwnerOK`、`KernelOK`、`TransferOK`、`JoinScan` 等关键谓词补到可独立判定的最小定义。

在上述动作未同时完成前，结论保持为：`未通过复审`。
