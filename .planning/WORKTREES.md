# 多 Worktree 并发协议

ReadLoop 的长程推进采用「每 phase 一个 worktree、main 为唯一集成区」的并发模型,与 GSD 的 phase 工作流叠加使用。

## 目录与命名

- 主仓(集成区):`/Users/zpc/projects/elsepage`(`main` 分支,**不做功能开发**)
- Worktree 根目录:`/Users/zpc/projects/elsepage-worktrees/`(按需自动重建)
- 分支命名:沿用 GSD config 的 `gsd/phase-{N}-{slug}`,如 `gsd/phase-1-trust`
- Worktree 目录名:phase 号前缀,如 `elsepage-worktrees/p1-trust`、`elsepage-worktrees/p5-bench`

## 并行波次(与 ROADMAP 对应)

```
v0.5:  p1-trust ‖ p2-library-today ‖ p3-journal ‖ p4-onboarding ‖ p5-bench
                           ↓ 全部合并后
       p6-polish-fixes(集成收尾,基于最新 main)

v1.0:  p7-a11y ‖ p8-providers ‖ p9-bench-judge(依赖 p5 产物)
                           ↓
       p10-release-compliance → p11-launch-gate
```

**协调点**(并发期已知交接):
- p2(Library/Today)与 p4(Onboarding)都触碰 Today 空态:先合并者在 main 上立住,后者 rebase 后适配;两者改动都应尽量薄
- p6 必须等 p1–p5 全部合并后再开 worktree,避免在上游移动时做全局面打磨

## 单个 phase 的生命周期

1. **开仓**:在主仓 `git worktree add ../elsepage-worktrees/p{N}-{slug} -b gsd/phase-{N}-{slug} main`
2. **规划**:在对应 worktree 内运行 `$gsd-plan-phase {N}`(或由 manager 后台调度);plan 文件随分支走
3. **执行**:在同一 worktree 内运行 `$gsd-execute-phase {N}`;GSD 产物(SUMMARY 等)照常写入该 worktree 的 `.planning/`
4. **集成**(满足以下全部才可合并):
   - worktree 内 `swift test` 全绿(所有 test target)
   - `git rebase main` 完成,冲突已解决
   - rebase 后再次 `swift test` 全绿
   - 在主仓 `git merge --no-ff gsd/phase-{N}-{slug}`
5. **收仓**:合并后在主仓统一执行——
   - 更新 `.planning/ROADMAP.md` 进度表与 `.planning/STATE.md`(勾选 plan、phase 状态)
   - 若 worktree 内 `.planning/` 有改动(如 SUMMARY),以 main 的 ROADMAP/STATE 为准合并,只搬运事实性产物
   - `git worktree remove` + `git branch -d`

## 冲突与纪律

- **后合并者负责 rebase 冲突**;冲突解决不得静默丢弃对方功能,拿不准时在 STATE.md 记 blocker
- **.planning 并发写**:进度类文档(ROADMAP/STATE)只在主仓合并后更新,worktree 内不手改这两份,避免合并冲突
- **集成频率**:phase 内每完成一个 plan 且测试绿,即可走一次小步合并(不必等整个 phase 完成);集成越频繁,rebase 痛苦越小
- **main 永远绿**:任何时刻 main 上 `swift test` 必须通过;合并前在主仓复跑一次
- **不越界**:phase worktree 不修改其他 phase 范围的文件;发现跨界需求时记入 STATE.md 的 Blockers 由主仓裁决

## 与 GSD 的关系

- `$gsd-manager` 在主仓运行,作全局看板;后台 plan/execute agent 需在提示中显式给出 worktree 路径作为 Working directory
- 里程碑切换(v0.5 → v1.0)走 `$gsd-complete-milestone` + `$gsd-new-milestone`,只在主仓执行
- verify(UAT 类)phase(6/11)含用户真机验收,在 manager 中 inline 跑,不要后台化

## 质量门槛(全 phase 生效)

- Agent 负责:开发 + `swift test` 全绿;不执行 xcodebuild 构建/模拟器/真机操作
- 用户负责:xcodebuild 构建、真机手测、TestFlight 上传,以及 phase 6/11 的验收签字
- 涉及真实 Provider 的联调(bench 跑批、Test Connection、验证矩阵):用户提供 API Key 后按 phase 内说明执行,Key 不入库不入日志
