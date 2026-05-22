# MoonBit Workflow / Parallel Runtime Spec 复审报告

## 结论

当前版本已经不再只是 `plan-only` 规范，而是开始引入 `workflow` 顶层对象、capability 协议和 native runtime 分层。审计基线也必须随之切换：我们现在审的不是“并行算子规范是否闭合”，而是“workflow 顶层、compute 子系统、capability 协议、native scheduler 层、OpenMP compute lane”这五层是否形成一个单一合同。

本轮结论是：`条件性推进，但仍未通过完整复审；后续提交必须继续把 workflow 顶层合同、native runtime 子集与 conformance 文档一起推进`。

当前剩余问题会直接破坏以下能力：

- 第三方独立实现时的唯一解释性；
- conformance claim 的可重复审计性；
- fail-closed 行为的统一判定；
- workflow semantic core 作为唯一规范源的权威性。

当前版本还额外闭合了两条此前悬空的语义：

- 阻塞式 `submit()` 的结果不再由包装层自行解释，而是定义性地返回最终
  `WorkflowResult.status`；
- 单个 `BarrierNode` 形成的导出 barrier group 被视为非法 group，并以
  `BARRIER_BROKEN` fail closed。

因此，不接受“runtime 先写、文档下轮再补”或“workflow 只是实验接口，不进入主规范”这类处理方式。后续提交必须持续保持：runtime 子集、workflow 顶层语义、native realization、validation scenarios、review baseline 同步演进。任何只推进其中一层的版本，仍应视为未完成闭合。

## Findings

### F1. workflow 已进入代码，但主规范仍有大量 plan-only 表述残留

- 严重级别：高
- 证据：
  - 代码中已经存在 `workflow` 顶层对象、`CapabilityKind`、`NodeKind`、`EdgeKind`、`WorkflowIssue`。见 [workflow.mbt](/Users/kcn/Desktop/repos/MoonVibe/luna_thread/luna_thread/workflow/workflow.mbt:1)。
  - facade 已暴露 `workflow(...)`、`compute_task(...)`、`spawn_task(...)`、`submit_workflow(...)`。见 [luna_thread.mbt](/Users/kcn/Desktop/repos/MoonVibe/luna_thread/luna_thread/luna_thread.mbt:114)。
  - 但英文/中文规范的 semantic core 主体仍是 `Plan` 顶层，而不是 `Workflow` 顶层。见 [docs/moonbit-parallel-spec-en.typ](/Users/kcn/Desktop/repos/MoonVibe/luna_thread/docs/moonbit-parallel-spec-en.typ:71)、[docs/moonbit-parallel-spec-zh.typ](/Users/kcn/Desktop/repos/MoonVibe/luna_thread/docs/moonbit-parallel-spec-zh.typ:66)。
- 问题分析：
  - 如果 workflow 已经是代码中的主接口，而文档仍把 plan 视为唯一顶层请求，那么第三方实现者就无法判断 workflow 到底是正式合同还是实验外壳。
  - 这会让 runtime、facade、文档三层再次分叉。
- 影响：
  - workflow 无法成为可审计的顶层请求。
  - 当前 facade API 的规范地位不明确。
-- 建议：
  - 把 `WorkflowWF`、capability 类别、node/edge 类别前移到 Part I 顶层。
  - 明确 `Plan` 只作为 `ComputeNode(plan)` 的子系统存在。

### F2. native runtime 已开始接受 workflow request，但规范尚未解释 scheduler layer 与 compute lane 的边界

- 严重级别：高
- 证据：
  - native C 头已经新增 workflow capability/node/edge/request 结构和 `luna_thread_workflow_submit(...)`。见 [luna_thread_runtime.h](/Users/kcn/Desktop/repos/MoonVibe/luna_thread/native/include/luna_thread_runtime.h:66)。
  - native runtime 已经对 workflow request 做 admission 检查。见 [runtime.c](/Users/kcn/Desktop/repos/MoonVibe/luna_thread/native/src/runtime.c:46)。
  - 但文档里的 Native Realization 仍只描述单层 `runtime descriptor -> C runtime` 模型。
- 问题分析：
  - 代码已经开始形成“两层 native realization”，但文档如果不承认 `scheduler layer + compute lane`，第三方实现者会误以为所有并发语义都还是单层 compute runtime 的扩展。
- 影响：
  - 无法判断 `pthread scheduler + OpenMP compute lane` 是否属于符合性实现，还是项目内部权宜之计。
-- 建议：
  - 把 Native Realization 改写成双层 runtime 模型。
  - 明确 compute node 通过独占 compute lane 执行，而不是在普通 scheduler worker 中递归开 OpenMP。

### F3. workflow capability 协议与 fail-closed 状态仍未形成新的审计闭环

- 严重级别：中高
- 证据：
  - workflow 代码里已经出现 capability/node 匹配、unsupported primitive rejection、cycle rejection。见 [workflow.mbt](/Users/kcn/Desktop/repos/MoonVibe/luna_thread/luna_thread/workflow/workflow.mbt:382)。
  - native runtime status 已开始扩展到 `UNSUPPORTED_RUNTIME_PRIMITIVE`、`RUNTIME_BROKEN`。见 [luna_thread_runtime.h](/Users/kcn/Desktop/repos/MoonVibe/luna_thread/native/include/luna_thread_runtime.h:9)。
  - 但复审报告和主规范都还没把这些新判据写成新的审计矩阵。
- 问题分析：
  - 如果 workflow capability 和新的 runtime status 只是代码存在、文档不承认，那么新的 fail-closed 语义就无法被第三方独立复核。
- 影响：
  - workflow 顶层无法形成新的 conformance baseline。
-- 建议：
  - 在主规范中新增 workflow validation scenarios。
  - 在复审报告里把 capability mismatch、cycle、unsupported runtime primitive 纳入新的审计基线。

## 审计意见

本轮审计仍不接受代码和规范分离推进。当前剩余问题已经收敛到 3 条主链路：

1. workflow 顶层是否正式替代 plan-only 顶层。
2. native runtime 双层结构是否被主规范承认。
3. capability 协议与 fail-closed 状态是否形成新的审计闭环。

这 3 条不是彼此独立的小问题，而是同一件事的三个表现：规范还没有形成可执行、可审计、可外包实现的单一合同。只修其中一条，另外两条仍会把整个规范重新拉回“实现自补”“审核自补”“口径漂移”的状态。

因此，本报告的管理性结论改写为：

- 不接受 workflow 只存在于代码、不进入主规范。
- 不接受 native scheduler / compute lane 只存在于实现、不进入 realization 章节。
- 不接受 capability 和 runtime status 的判定只靠 reviewer 推断。

下一轮必须继续完成以下闭合动作：

1. 把 workflow/capability 顶层语义写入 semantic core。
2. 把 native scheduler + compute lane 写入 realization 章节。
3. 把 workflow validation / capability mismatch / unsupported primitive / cycle rejection 写入 conformance 与 validation matrix。

在上述动作继续同步完成前，结论保持为：`未完成闭合复审`。
