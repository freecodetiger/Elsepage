# DEBUG 业务测试闭环

GSD quick：用户授权落地架构方案。保持现有 Swift 包结构、业务语义和用户构建分工。

1. DEBUG loopback HTTP 传输，令牌验证、有界请求、手动生命周期。
2. 独立内存 GRDB 环境，调用真实 SessionReflectionModel.submit，暴露动作、模型/持久化快照、关联事件和已有性能报告。
3. Mac 标准库执行器验证保存、读取与失败，输出证据；接入诊断页。
4. swift test、脚本验证、工程文件登记；真机服务连通性和 App 构建交用户验收。

首批能力限定 Reflection 保存，Agent 联调/Brain 后台任务完成协议留后续，不冒充已覆盖。
