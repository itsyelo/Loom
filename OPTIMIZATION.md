# Loom 项目优化分析报告

> 分析范围：`Sources/Loom/`（约 2,400 行）、`Tests/LoomTests/`（约 750 行）、`Package.swift`、README。
> 日期：2026-07-03

Loom 整体设计清晰：值类型节点树 + Yoga 桥接 + Core Text 测量 + 缓存层，模块边界干净，DocC 文档和注释质量高。以下按优先级列出值得优化的问题。

---

## 一、正确性问题（高优先级）

### 1. `.position()` 以 `0` 作为"未设置"哨兵，显式传 `0` 会被静默忽略

**位置**：`Sources/Loom/Engine/LoomEngine.swift:303-308`、`Sources/Loom/API/LoomStyle.swift:92`

`LoomEdgeInsets` 用非可选 `CGFloat`（默认 0）存储 position 偏移，`applyStyle` 里用 `pos.top != 0` 判断是否下发给 Yoga：

```swift
if pos.top != 0 { node.setPosition(.top, Float(pos.top)) }
```

对 padding/margin 来说 0 是无害的 no-op，但对 absolute position，**`top: 0`（钉在顶部）和"未设置"（按容器 justify/align 排布）语义完全不同**。`LoomNode.swift:224-228` 文档示例本身就写了 `.position(type: .absolute, top: 0, trailing: 0)` —— 两个值都会被跳过，只是在默认 `justify: .start` 容器里"碰巧"表现正确；一旦容器是 `justify: .center`，徽标就不再贴顶。

**建议**：`LoomStyle.position` 改用可选字段（如独立的 `LoomPositionInsets`，字段类型 `CGFloat?`），`applyStyle` 改为 `if let`。这是 API 语义修复，越早改破坏面越小。

### 2. `LayoutCache` 的字符串拼 key 存在冲突与误删

**位置**：`Sources/Loom/Cache/LayoutCache.swift:131-133, 27-36`

```swift
private func cacheKey(id: some Hashable, width: CGFloat) -> String {
    "\(id)-\(width)"
}
```

两个问题：

- **key 冲突**：依赖 `String(describing:)` 而非 `Hashable`。不同类型/不同值的 id 只要字符串描述相同就会串缓存（如 `Int 1` 与 `String "1"`，或自定义类型 description 重叠）。
- **`invalidate(id:)` 前缀误伤**：`invalidate(id: "post")` 用前缀 `"post-"` 匹配，会把 `id: "post-2"` 的所有条目一并删除。feed 场景里 `"item-1"` / `"item-12"` 这类 id 很常见（`"item-1"` 的前缀 `"item-1-"` 恰好命中 `"item-12-..."`？不会，但 `"item-1"` 会命中 `"item-1-extra"`），踩中即静默丢缓存或多删。

**建议**：改用结构化 key —— 一个包装 `AnyHashable id + CGFloat width` 的 `NSObject` 子类（实现 `hash`/`isEqual`）作为 NSCache key；`invalidate` 按 id 精确匹配而非字符串前缀。

### 3. `LayoutCache.knownKeys` 无限增长（内存泄漏）

**位置**：`Sources/Loom/Cache/LayoutCache.swift:7, 21-23`

`NSCache` 到达 `countLimit` 后会自动驱逐条目，但 `knownKeys` 只在显式 `invalidate` 时移除。长期滚动的 feed（成千上万个 id 流过、cache 上限 200）会让 `knownKeys` 无界增长。

**建议**：实现 `NSCacheDelegate.cache(_:willEvictObject:)` 同步清理；或干脆放弃 NSCache，用带锁的字典 + 简单 LRU 自管理（顺带解决问题 2 的 key 结构问题）。

### 4. 根节点是"带 padding 的 leaf"时，keyed frame 语义不一致

**位置**：`Sources/Loom/Engine/LoomEngine.swift:62-67, 321-330`

带 padding 的 leaf 会被自动包一层容器，文档承诺"key 的 frame 对应内容区"。但当这样的节点**直接作为根**时，`extractFrames` 把包装容器的 frame（含 padding）记到 key 下 —— 与作为子节点时（记录内层内容 frame，见 `LoomEngine.swift:374-386`）行为不一致。

**建议**：在 `extractFrames` 根路径上对 wrapped-leaf 做与子节点相同的内层展开；补一条根级 leaf+padding+key 的单测。

### 5. `YogaConfig` 的线程安全与潜在死锁

**位置**：`Sources/Loom/Bridge/YogaConfig.swift:6, 22-37`

- `scaleConfigured` 无锁读写，多线程首次 `calculate()` 并发时是数据竞争（标了 `@unchecked Sendable` 但没有实际同步）。
- `ensureScaleConfigured()` 在后台线程走 `DispatchQueue.main.sync`：如果主线程恰好在同步等待这次后台布局（信号量/`.wait()` 模式在预排版场景不罕见），会直接死锁。
- `UIScreen.main` 已在 iOS 16 起被废弃。

**建议**：用 `NSLock` 保护配置状态；scale 获取改为启动时（或首次主线程调用时）缓存一次，后台路径绝不 `main.sync`——拿不到就先用 `UITraitCollection.current.displayScale` 或默认 3.0，并在文档中引导显式调用 `Loom.configure(screenScale:)`。

---

## 二、性能优化（中优先级）

### 6. 每次 `calculate()` 全量重建 Yoga 树

**位置**：`Sources/Loom/Engine/LoomEngine.swift:31, 62-131`

每次计算都要：为每个节点分配 `YogaNode` 类实例 + `YGNodeNew` + 闭包装箱（text/measured 节点），算完随即整树释放。对高频路径（滚动中实时反算、宽度变化重排）这是纯粹的分配抖动。`.plans/task-17-persistent-tree.md` 已有持久化树的规划，值得提上日程：

- 短期：`YGNode` 对象池，复用已释放的节点；
- 长期：`LoomLayout` 持有可复用的 Yoga 树，diff 式更新 style 后调 `YGNodeCalculateLayout`（Yoga 本身支持脏标记增量计算，重建树等于放弃了这个能力）。

### 7. `extractFrames` 与 `extractFramesFromChild` 约 180 行近似重复

**位置**：`Sources/Loom/Engine/LoomEngine.swift:314-494`

ZStack 对齐后处理、wrapped-leaf 内层展开这两段最容易出 bug 的逻辑各写了两遍（问题 4 正是这种双份维护漏掉的产物）。可统一为单一递归 `extract(yogaRef:loomNode:parentAbsX:parentAbsY:)`，根节点只是 `parentAbs = (0,0)` 的特例。纯重构，行为不变，测试已足够护航。

### 8. `FramesetterCache` 以 `NSAttributedString` 作 NSCache key 的查找成本

**位置**：`Sources/Loom/TextMeasure/TextMeasurer.swift:161, 172-196`

NSCache 用 `hash`/`isEqual` 比较 key：`NSAttributedString` 的 `hash` 只基于纯文本，`isEqual` 则全文 + 全属性比较。同一段长文不同属性（如展开/折叠态不同颜色）会哈希碰撞后逐一 `isEqual`，长文本下每次查找是 O(n) 字符串比较。量级不大但在滚动热路径上可测。可选优化：key 换成"文本 hash + 属性指纹"的轻量包装对象，或允许调用方传入业务 id 作为缓存键。

### 9. GCD + continuation 混用，且并发 resolve 无去重

**位置**：`Sources/Loom/API/LoomLayout.swift:72-80`、`Sources/Loom/Cache/LayoutCache.swift:96-129`

- `calculateAsync` / `resolveAsync` 用 `withCheckedContinuation + DispatchQueue.global`。在 Swift Concurrency 语境下更直接的是 `Task.detached` / 后台 actor，避免协作线程池与 GCD 池双重占用（over-commit）。最低部署 iOS 14，无兼容负担（`@available(iOS 13, ...)` 标注也已冗余）。
- `resolveAsync` 存在 thundering herd：同 id+width 并发调用各算各的。可加 in-flight `Task` 字典去重（首个调用创建 Task，后来者 await 同一个）。

---

## 三、API 设计与工程化（低优先级）

### 10. `Spacer` 只支持"垂直高度"，在 HStack 中无效

`NodeFactories.swift:153-157` 的 `Spacer(_:)` 只设 `height`，放进 HStack 不占任何主轴空间，与 SwiftUI 心智相悖。建议：无参 `Spacer()` = `flexGrow: 1` 的弹性占位；`Spacer(12)` 沿父容器主轴生效（需要在引擎侧感知父方向，或提供 `HSpacer`/`VSpacer`）。

### 11. `Loom.debugOptions` 是 `nonisolated(unsafe)` 全局可变量

`LoomConfig.swift:21`。后台布局读取时若主线程正在写入是数据竞争。仅 DEBUG 生效，危害有限，但既然全库都在往 StrictConcurrency 靠，可以低成本换成原子存储（`OSAllocatedUnfairLock` 或 atomics）。

### 12. 调试颜色用 `String.hashValue` —— 每次启动都变色

`LoomBindings.swift:107`。Swift 的 String 哈希每次进程启动随机加盐，同一个 key 两次运行颜色不同，不利于跨启动对比截图。换 FNV-1a/djb2 等确定性哈希即可。

### 13. `LoomBindings.apply` 缺主线程断言

直接写 `view.frame`，如果调用方在后台误用会得到难排查的渲染问题。加 `assert(Thread.isMainThread)`（或 `MainActor.assumeIsolated`）成本为零。

### 14. 工具链与工程配套

- **Swift 6 语言模式**：目前是 5.9 tools + `enableExperimentalFeature("StrictConcurrency")`，可升级 `swift-tools-version: 6.0` 用正式的 `.swiftLanguageMode(.v6)`，顺带把 `Kind: @unchecked Sendable`（`LoomNode.swift:21`）里对 `NSAttributedString` 不可变的假设用注释显式固定下来。
- **无 CI**：仓库没有任何 workflow。建议加 GitHub Actions：macOS runner 上 `swift build` + `swift test`（iOS Simulator destination），保护 747 行既有测试。
- **无 LICENSE**：README 已宣传 SPM 安装（`from: "1.0.0"`），开源分发缺 LICENSE 文件是硬伤。
- **README 与 RTL 事实不符的小措辞**：HStack 描述为 "left to right"，但已支持 RTL 时会翻转，建议改为 "沿阅读方向"。

### 15. 测试盲区

现有 38 个测试对布局语义、RTL、文本测量覆盖很好，但以下无覆盖：

| 盲区 | 关联问题 |
|---|---|
| `LayoutCache.invalidate` 的 id 隔离（`"a"` vs `"a-b"`） | 问题 2 |
| 缓存驱逐后 `knownKeys` 状态 | 问题 3 |
| 根级 leaf + padding + key 的 frame 语义 | 问题 4 |
| `.position(top: 0)` 在非默认 justify 容器中的行为 | 问题 1 |
| `calculateAsync` / `resolveAsync` / `precalculateAsync` 全部无测试 | 问题 9 |
| `LoomBindings.apply`（含 relative(to:) 路径、weak view 释放） | — |

---

## 四、文本测量一致性的重新评估（2026-07-03，第二批）

### 背景

Loom 默认用 Core Text（`CTFramesetterSuggestFrameSizeWithConstraints`）测量，UILabel 用 TextKit 渲染，两个引擎对行高/leading 的处理有细微差异——CT 测出的 N 行高度可能比 UILabel 实际需要的少几个点，导致提前截行。现行文档方案（MultilineUILabelTips）是给 attributedString 锁定 min/max lineHeight，强迫两个引擎一致。

### 为什么锁行高不够优雅

1. **逐调用点纪律**：每个多行文本都要记得锁，漏一处就截行。Example 自己就踩了两次（bio、Showcase caption）。
2. **污染设计值**：锁 min=max 到最高字体的 lineHeight 会改变混排文本的视觉节奏——这是为了测量正确性去改内容样式，本末倒置。
3. PR #14 已经给出了正确的抽象（`TextMeasuring` 插件点），但没有配套的 UILabel 原生测量器，等于插座建好了没有插头。

### 建议方案（PR A′）

1. **新增 `TextKitMeasurer: TextMeasuring`** —— 用 NSLayoutManager + NSTextContainer（`maximumNumberOfLines` 原生支持 maxLines）测量，每次调用新建独立 TextKit 栈保证线程安全。测出的尺寸与 UILabel 布局**天然一致**，任意 attributedString 无需任何 paragraphStyle 纪律。
2. **新增 `Loom.defaultTextMeasurer` 全局默认**（线程安全存储），`Text()` 工厂的默认值从硬编码 `TextMeasurer.shared` 改为读取它。App 启动时一行 `Loom.defaultTextMeasurer = TextKitMeasurer.shared` 即可全局切换——逐调用点纪律彻底消失。
3. **文档重新定位**：锁行高从"必须的纪律"降级为"高性能选项"——CT + framesetter 缓存在重复测量同一字符串时仍更快，热路径（高频重算）可继续用 CT + 锁行高；一次性流水线（每条数据只算一两次）用 TextKitMeasurer 更省心。
4. **边界澄清（实现时确认）**：锁行高实际解决的是另一个独立问题——UILabel 在 `numberOfLines` 0↔N 切换时的内部渲染模式切换导致首行跳动（MultilineUILabelTips 的主题）。这是渲染层怪癖，与测量无关，TextKitMeasurer 不解决它。正确分工：**提前截行/底部空白 → TextKitMeasurer**；**折叠展开首行跳动 → 锁行高（仅 toggle 场景需要）**。两个工具各管一个问题，文档按此重构。
5. **可发现性（评审中确认的真实盲区**——分析者通读全部源码后仍未把 TextMeasuring 与 UILabel 截行问题联系起来，因为现有文档把它框定为"非 UILabel 渲染器专用"）：
   - **DEBUG 运行时诊断**：`LoomBindings.apply` 绑定 UILabel 时对比 measured frame 与 `sizeThatFits`，偏差超阈值即警告并指向文档——把静默截行变成大声失败，这是比任何文档强调都强的杠杆；
   - **入口决策表**：GettingStarted / FeedListPipeline 开头摆明"测量与渲染必须选一种对齐方式"（TextKitMeasurer 零纪律 vs CT+锁行高高性能）；
   - **症状优先排障**：MultilineUILabelTips 增加"文本提前截断/底部空白？"小节；TextMeasuring 的定位从"自定义渲染器"改写为"测量-渲染一致性的统一机制"。

### 取舍说明

- 性能：TextKit 单次测量成本与 CT 同量级，但没有 framesetter 缓存加成；对"每条数据算一次"的流水线场景无感，对高频重算场景 CT 路径仍是首选。
- TextKit 1 对象不可跨线程共享，但"每次测量新建栈"是成熟安全模式（Texture 的 ASTextKit 同理）。

## 五、能力边界（按需实现，每项独立 PR）

以下不是缺陷而是功能边界。接入真实项目前拿实际 cell 清单对照，确认有真实需求再实现——避免无需求驱动的 API 设计。

| 能力 | 现状 | 设计要点 |
|---|---|---|
| **百分比尺寸** | Yoga 原生支持（`YGNodeStyleSetWidthPercent` 等），Loom 未暴露 | 引入 `LoomDimension`（point/percent 二态），`width/height/minW/maxW/flexBasis` 全套换型；是破坏性变更，越早做成本越低 |
| **baseline 对齐** | Yoga 支持 `align: .baseline` + baseline 回调，Loom 的 `LoomAlign` 未包含 | **地基已铺**：`TextMeasurement.firstBaseline/lastBaseline`（feat/text-measurement-details）。剩余工作：`LoomAlign.baseline` + 引擎侧 baseline 回调接线 |
| **截断 token（"查看更多"）** | 无 | **地基已铺**：`TextMeasurement.visibleRange`（自然断点即 token 插入点）+ `lastLineWidth`（token 摆放位置）。剩余工作：测量时为 token 预留宽度的迭代算法 + 渲染层拼接约定 |

## 六、建议的执行顺序与进度

> 2026-07-03 更新：第一批修复已落地，42 个测试全绿（37 旧 + 5 新回归测试）。

1. ✅ **问题 1（position 哨兵）** —— 新增 `LoomPosition`（全可选字段），`LoomStyle.position` 换型，引擎按 `if let` 下发；显式 `0` 现在正确钉边。回归测试 `testPositionExplicitZeroPinsToEdge`。
2. ✅ **问题 2 + 3（LayoutCache 重写）** —— 弃用 NSCache + 字符串拼 key，改为 `AnyHashable id + width` 结构化 key + 带锁字典 + tick-LRU；`invalidate(id:)` 精确匹配；iOS 上收到内存警告自动清空。回归测试 `testInvalidateIsScopedToExactId` / `testDistinctIdTypesDoNotCollide` / `testLRUEvictsLeastRecentlyUsed`。
3. ✅ **问题 4 + 7（extractFrames 合并重构 + 根级 wrapped-leaf 修复）** —— 双份提取逻辑合并为 `recordFrame` + `extractChildFrames` 单一递归；根级带 padding 的 leaf 现在同样返回内容区 frame。回归测试 `testRootLeafWithPaddingKeyReturnsContentFrame`。
4. ✅ **问题 5（YogaConfig 同步）** —— 配置状态加 `NSLock`；后台首次布局不再 `main.sync`（消除死锁），改为临时 3.0 fallback + `main.async` 一次性捕获真实 scale，文档引导显式 `Loom.configure(screenScale:)`。
5. ✅ **CI** —— `.github/workflows/ci.yml`：macOS `swift test` + iOS Simulator `xcodebuild build`（本地已验证两条路径均通过）。**LICENSE 仍缺**——选择何种许可证是作者决策，未代做。
6. ❌ **问题 6（持久化 Yoga 树）** —— 已评估为**不做**：目标使用模式是"数据到达时子线程一次性算好、ViewModel 持有 LayoutResult"，每条数据一生只算一到两次，增量重算无用武之地；而持久化树会破坏现有"建树→计算→释放"的任意线程安全模型。若将来出现每帧驱动布局的场景，先做 YGNode 对象池。
7. ⬇️ **问题 9（异步去重）** —— 优先级下调：ViewModel 流水线模式下不存在并发重复计算入口。
8. ⬜ 其余（问题 8、10–15）按需排入。其中 iOS 构建时 `LoomBindings.swift` 有数条 Swift 6 主线程隔离 warning，与问题 13（主线程断言）可一并处理。
