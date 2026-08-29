# Phase 15: Persistent Embedding + BrainRetriever — Summary

**Date:** 2026-08-29
**Status:** Complete — `swift test` 343/343 全绿(新增 5 个行为级测试);纯包层改动,App target 无变化
**Spec:** `docs/brain.md` §6,§12,§20 Phase 4 · Plan: `15-01-PLAN.md`

## What shipped

1. **`brainItemEmbeddings` 持久化(v23 迁移)**:PK(brainItemID, model)——换模型保留旧行(与 bookChunkEmbeddings 同策略);FK CASCADE 到 brainItems,条目删除向量自动清理,无手动 GC;`wipeAllUserData` 覆盖。
2. **`BrainEmbeddingStore` 协议 + `BrainItemVector`**(BrainCore,含 contentHash),GRDB 实现(`GRDBBrainEmbeddingStore`),Float↔Blob 往返照抄 BookIndexRepository 模式,维度不符在解码层拒绝。
3. **`BrainRetriever`**(ContextEngineering,与 MemoryRetriever 同族同模式):
   - 词法通道:CJK 分词、query tokens ≥2、overlap 相关度 ≥0.30(与 MemoryRetriever 完全同款);
   - 语义通道:读**持久化**向量,`contentHash`(SHA256,公开静态方法,Phase 17 复用)比对——仅缺失/过期/维度不符者重 embed,单次刷新上限 16 条;cosine 阈值 0.2;
   - 融合:HybridFusion RRF;输出 `BrainCandidate { item, lexicalScore, semanticScore }`;
   - 退化链:无 store/provider 或 embed 失败 → 纯词法,不崩;
   - 资格过滤:kinds 集合;memory superseded/forgotten 排除;thought archived 排除;候选池最近 30 条。
4. **Package.swift**:ContextEngineering 增加 BrainCore 内部依赖(无新产品,无需 xcodegen)。

## Test-notes(recorded)

- 词法阈值是按 token 数算的:中文查询"自由是不是意味着责任"(9 bigram)与条目仅重叠"自由/责任"→ 0.22 < 0.30 不命中;测试用例最终用"自由与责任"(5 token,2/5=0.4)。这不是实现 bug——门槛与 MemoryRetriever 一致,长查询需要更高重叠。
- 计数 provider 的调用计数用 actor(NSLock 在 async 上下文不可用)。

## Verification

- `swift test` 343/343;迁移清单断言已含 `v23_brain_item_embeddings`。
- 关键断言:内容未变的二次检索**只 embed 查询本身**(item 零重嵌)——"创建一次、反复检索"成立。

## Next

Phase 16(Agent Bridge):BrainContextProvider 把 BrainCandidate 适配为 ContextCandidate 进入 ContextAssembler;Pinned Context(activeBrainContext)。→ Phase 17 BrainProjectionService(生产写入方)。
