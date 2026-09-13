# DEBUG 测试闭环 v1

完成：USB loopback HTTP、手动启停与令牌、状态/性能读取、真实 Reflection Model 保存、隔离 GRDB 环境、动作去重与有界事件、Mac 场景执行器及证据输出。

验证：349 Swift Testing + 26 XCTest；Python 2 测试；xcodegen 工程登记。App 构建/真机服务/USB 转发待用户执行，步骤见 docs/DEBUG-LOOP.md。

实现选择：独立装配测试所需最小对象图，复用产品 Model/Repository；没有为首场景重写完整 AppModel。Agent/Brain 不列入已支持能力。

用户构建反馈修复：动作查询路径的 dropFirst 参数误传字符串，改为前缀字符数。App 编译仍由用户验证。

自动连接改进：用户明确授权取消认证，DEBUG AppModel.start 自动开启 loopback 服务；Mac 脚本不再读令牌，按调用复用或启动 iproxy，识别旧版401。Python 5测试通过；新设备构建待用户安装验证。
