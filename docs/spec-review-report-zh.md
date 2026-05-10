# MoonBit Parallel FFI Spec 复审报告

## 结论

当前版本相较前两轮已经明显收敛，之前报告中的几项主问题已经被修复，包括：

- `OutRef`、`ShapeOK`、`Den(p)` 已补入正文。
- `scan` / `map-reduce` 已进入语义层文本。
- `TransferLifecycleReject` 与 `JSLifecycleReject` 已加入失败状态代数。
- `SharedArrayBuffer` 已增加 snapshot 义务。

因此，旧报告中的主要结论已不再适用。

本轮复审结论是：`规范已进入可用阶段，但仍不建议以“语义闭合且可直接作为独立实现/符合性认证基准”的状态通过`。当前剩余问题不在大框架，而在若干关键合同之间仍有不一致。

## Findings

### F1. `AccessMode` 与 `OutRef` 的权限合同仍不自洽

- 严重级别：高
- 证据：
  - `AccessMode` 只定义在 `BufferRef` 上，`OutRef` 不带 `AccessMode`。见 [docs/moonbit-parallel-spec-en.typ](/Users/kcn/Desktop/repos/MoonVibe/luna_thread/docs/moonbit-parallel-spec-en.typ:111)、[docs/moonbit-parallel-spec-en.typ](/Users/kcn/Desktop/repos/MoonVibe/luna_thread/docs/moonbit-parallel-spec-en.typ:120)、[docs/moonbit-parallel-spec-en.typ](/Users/kcn/Desktop/repos/MoonVibe/luna_thread/docs/moonbit-parallel-spec-en.typ:127)。
  - 但 `ShapeOK` 又要求 `ReducePlan` / `MapReducePlan` 的 `out` “is writable”。见 [docs/moonbit-parallel-spec-en.typ](/Users/kcn/Desktop/repos/MoonVibe/luna_thread/docs/moonbit-parallel-spec-en.typ:164)、[docs/moonbit-parallel-spec-en.typ](/Users/kcn/Desktop/repos/MoonVibe/luna_thread/docs/moonbit-parallel-spec-en.typ:168)。
  - 对 `MapPlan`、`ScanPlan`、`MapReducePlan`，规范要求目标 buffer 可写，但没有对源 buffer 的可读性作对称约束；按当前文本，`src` 形式上仍可能是 `WriteOnly`。见 [docs/moonbit-parallel-spec-en.typ](/Users/kcn/Desktop/repos/MoonVibe/luna_thread/docs/moonbit-parallel-spec-en.typ:163)、[docs/moonbit-parallel-spec-en.typ](/Users/kcn/Desktop/repos/MoonVibe/luna_thread/docs/moonbit-parallel-spec-en.typ:166)、[docs/moonbit-parallel-spec-en.typ](/Users/kcn/Desktop/repos/MoonVibe/luna_thread/docs/moonbit-parallel-spec-en.typ:168)。
  - 后文又要求 facade 为每个导出的 boundary view 绑定显式 ownership mode 与 access mode。见 [docs/moonbit-parallel-spec-en.typ](/Users/kcn/Desktop/repos/MoonVibe/luna_thread/docs/moonbit-parallel-spec-en.typ:722)。
- 问题分析：
  - 现在的文本已经表达出“哪些位置应当可写”，但没有把它落实为统一的类型合同。
  - `OutRef` 如果本来设计成“天然只写”，那需要明文定义；否则“writable”只是自然语言要求，而不是结构化约束。
  - 源输入的可读性也仍停留在默认常识，尚未进入 `ShapeOK` / `PlanWF`。
- 影响：
  - 计划良构性、wrapper admission、kernel arity/access 校验会在不同实现里出现自由解释空间。
  - 这会直接削弱 `ArityMeta`、`OwnerOK`、`KernelOK` 这类检查的可重复审计性。
- 建议：
  - 二选一：
    - 给 `OutRef` 增加显式 `AccessMode`；或
    - 明确规定 `OutRef` 在语义上恒为 write-only/result-only 引用。
  - 在 `ShapeOK` 中显式写出每个构造子的 source 必须 readable，destination 必须 writable。
  - 把这些访问性约束纳入 `PlanWF`，不要只停留在自然语言描述。

### F2. `scan` 的并行语义仍未与现有 footprint / metadata 合同打通

- 严重级别：高
- 证据：
  - `ScanStep` 被加入 worker 语法，但它只展示了单步把局部状态 `s` 与当前元素组合后写到目标地址。见 [docs/moonbit-parallel-spec-en.typ](/Users/kcn/Desktop/repos/MoonVibe/luna_thread/docs/moonbit-parallel-spec-en.typ:465)、[docs/moonbit-parallel-spec-en.typ](/Users/kcn/Desktop/repos/MoonVibe/luna_thread/docs/moonbit-parallel-spec-en.typ:513)。
  - `Spawn(d, I_i)` 的 `scan` 规则只说“left-to-right join writes the inclusive prefix result”，没有定义 chunk 之间前缀 carry 如何产生、保存、传播。见 [docs/moonbit-parallel-spec-en.typ](/Users/kcn/Desktop/repos/MoonVibe/luna_thread/docs/moonbit-parallel-spec-en.typ:569)。
  - 与此同时，worker footprint 被限制在 `AddrOf(I_i) union MetaOf(d)`，且 `MetaOf(d)` 必须只读。见 [docs/moonbit-parallel-spec-en.typ](/Users/kcn/Desktop/repos/MoonVibe/luna_thread/docs/moonbit-parallel-spec-en.typ:549)、[docs/moonbit-parallel-spec-en.typ](/Users/kcn/Desktop/repos/MoonVibe/luna_thread/docs/moonbit-parallel-spec-en.typ:550)、[docs/moonbit-parallel-spec-en.typ](/Users/kcn/Desktop/repos/MoonVibe/luna_thread/docs/moonbit-parallel-spec-en.typ:551)。
- 问题分析：
  - 对并行 prefix-scan 来说，chunk-local scan 之外通常还需要 chunk 间 prefix carry 的规范故事。
  - 当前文本已经定义了目标结果，但还没有定义“这些跨 chunk 信息属于哪里”：是 descriptor 预先携带、是只读 metadata 的一部分、是 join 阶段单独计算，还是允许额外 scratch 区。
  - 结果是：`scan` 的 denotation 已有，但对应的并行实现合同还没有完全落在现有 small-step + footprint 框架里。
- 影响：
  - 不同实现可能都声称符合 `Den(ScanPlan(...))`，但采用彼此不可比较的 chunk-carry 机制。
  - 现有数据竞争自由定理也无法直接说明这些 carry 机制是否被合同覆盖。
- 建议：
  - 在规范中显式引入 `scan` 的 chunk summary / carry contract。
  - 说明 carry 数据是否属于：
    - 额外的只读 descriptor metadata；
    - 单独的 audited scratch region；
    - join 阶段的顺序组合状态。
  - 若允许 scratch region，需要把它纳入 footprint 与 separation 合同；若不允许，需要把 `scan` 实现限制写得更明确。

### F3. JS `SharedArrayBuffer` 的 snapshot-by-copy 与 borrow 轨迹存在语义错位

- 严重级别：中高
- 证据：
  - JS 边界规则把 `SharedArrayBuffer` 的 admitted path 建模成 `Borrow_MR(b) * Borrow_C(b)`。见 [docs/moonbit-parallel-spec-en.typ](/Users/kcn/Desktop/repos/MoonVibe/luna_thread/docs/moonbit-parallel-spec-en.typ:605)、[docs/moonbit-parallel-spec-en.typ](/Users/kcn/Desktop/repos/MoonVibe/luna_thread/docs/moonbit-parallel-spec-en.typ:607)。
  - 但 snapshot 义务又允许实现通过 “copying, freezing, or an observationally equivalent mechanism” 来实现该 snapshot。见 [docs/moonbit-parallel-spec-en.typ](/Users/kcn/Desktop/repos/MoonVibe/luna_thread/docs/moonbit-parallel-spec-en.typ:625)、[docs/moonbit-parallel-spec-en.typ](/Users/kcn/Desktop/repos/MoonVibe/luna_thread/docs/moonbit-parallel-spec-en.typ:627)。
  - 同一份规范又要求 wrappers 保持 ownership fidelity。见 [docs/moonbit-parallel-spec-en.typ](/Users/kcn/Desktop/repos/MoonVibe/luna_thread/docs/moonbit-parallel-spec-en.typ:754)。
- 问题分析：
  - 如果 admitted path 在所有权上被建模成“借用原始共享缓冲区”，而实际执行却可以改为“复制后读取 snapshot”，那么执行依赖的物理对象与所有权轨迹描述的对象就不再一致。
  - 这不一定是错误设计，但当前 spec 需要在“借用语义”和“snapshot 实现语义”之间选一个更精确的表述。
- 影响：
  - 现有文本下，第三方实现者很难判断：
    - snapshot-by-copy 仍算 borrow path；
    - 还是应当转写成 copy path 并拥有新的 buffer identity；
    - 或者只是对 borrow path 允许的一种不可观察实现细节。
  - 这会影响 ownership trace、validation case 和 JS lifecycle reject 的判定口径。
- 建议：
  - 明确以下三者之一：
    - snapshot copy 是纯实现细节，不改变规范所有权轨迹；
    - snapshot copy 必须分配新的规范 buffer identity，并按 copy path 记账；
    - `SharedArrayBuffer` admitted borrow 只允许 freeze / pin / equivalent non-copy mechanisms。
  - 如果继续允许 copy，但又不想改变 ownership trace，需要明确“该 copy 在规范层不可观察”的理由和边界。

## 审计意见

这版 spec 的主要问题已经不再是“缺章节”或“缺大框架”，而是局部合同之间尚有几处没完全对齐。整体质量已经明显高于前两版，但要达到可以直接支撑第三方独立实现与符合性认证的标准，至少还需要完成：

1. 访问权限合同统一化。
2. `scan` 并行 carry 机制的规范化。
3. JS snapshot 与 borrow/copy 轨迹的对齐。

在这三点补齐前，我建议结论仍保持为：`需要修改后复审`。
