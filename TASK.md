# 当前任务状态

## 1. 任务背景

当前任务围绕 Salesforce 请假审批系统的扩展性增强展开，目标是让系统从“可用的基础请假审批”演进为“支持长期制度扩展、年度结转、工龄递增、跨年拆分和配置化审批策略”的方案。

本阶段优先策略：

- 先完善系统设计
- 再分阶段落地实现
- 避免一次性重构导致风险过高

---

## 2. 已完成事项

### 2.1 设计文档

`DESIGN.md` 已完成以下增强：

- 增加扩展性增强设计章节
- 增加假种配置化设计
- 增加余额明细与余额流水设计
- 增加年度重置、结转、过期失效设计
- 增加工龄递增年假设计
- 增加跨年请假拆分扣减设计
- 增加审批策略配置化设计
- 增加报表与指标设计

### 2.2 已落地代码

### 2.1.1 最新部署状态

已完成一次面向当前默认开发 org 的增量部署：

- 目标 org：`test`（Developer Edition / ChangYou）
- 已部署内容：
  - 假种配置对象与字段
  - 跨年 Segment 对象与字段
  - 年假结转相关余额字段
  - 请假申请审批快照字段
  - 审批历史快照字段
  - 年度结转、跨年分段、审批路由、审批历史相关 Apex 类
  - `Leave_Admin` Permission Set 最新变更
- 部署方式：
  - 由于项目全量部署会被 `quickActions` 子目录触发 CLI 类型推断问题，当前采用“按依赖分组 + 按变更文件”方式完成增量部署
  - 部署前已中止 org 中阻塞 `LeaveExpiryBatch` 覆盖的定时作业
- 随后又对当前工作区中仍显示变更的核心文件执行了二次增量部署，结果显示大部分组件已与 org 保持一致，未重复创建

---

仓库中已完成的阶段性实现包括：

仓库中已完成的阶段性实现包括：

- 在 `Leave_Balance__c` 上补充年假结转相关字段
- 新增年度结转与过期服务
- 新增年假策略读取服务雏形
- 新增 `Leave_Type_Definition__c` 配置对象基础元数据
- 在申请单中增加假种策略快照字段
- 提交校验与年假扣减已接入部分策略化逻辑
- 新增 `Leave_Request_Segment__c` 对象与跨年分段服务
- 跨年请假提交校验已按年度分段计算余额
- 跨年请假审批扣减已按年度分别扣减余额
- 新增审批模式、自动审批阈值、升级审批目标等审批策略字段
- 提交申请已支持按假种策略路由到经理审批、HR 审批或自动批准
- 经理审批通过后已支持按策略升级到 HR 审批
- 新增统一审批历史服务，收口申请提交、审批通过、驳回、自动取消等历史写入
- 审批历史已支持记录审批模式快照与审批目标快照
- 审批人来源已支持统一解析经理、HR 目标与自动审批来源

### 2.3 已补测试

已补充的测试方向包括：

- 年假结转创建与重复执行保护
- 结转额度到期失效
- 年假优先消耗结转额度
- 假种配置读取
- 假种停用后阻止提交
- 申请单保存策略快照
- 跨年请假分段生成
- 跨年请假按年度校验与扣减
- 审批策略读取与状态路由
- 自动批准与经理后升级 HR 的状态流转
- 审批历史快照写入
- 审批目标与审批来源解析
- 自动批准场景下 `Submitted + Approved` 双历史写入
- `LeaveExpiryBatch` 自动取消场景下 `Cancellation` 历史写入

最近一次 org 内测试执行结果：

- 执行目标 org：`test`
- 测试类：
  - `LeaveHomeControllerTest`
  - `LeaveServiceTest`
  - `LeaveTypePolicyServiceTest`
- 通过率 `100%`
- 共执行 `24` 个测试方法
- 最近 Test Run Id：`707NS00002IjNDy`
- 说明：本次为首页新建申请入口收口后的定向回归，已覆盖 definition 驱动的 Draft 创建、可选假种过滤、提交流程、审批流程与余额校验
  - `LeaveService` = `88%`
  - `LeaveTypePolicyService` = `88%`
  - `LeaveRequestHandler` = `83%`
  - `LeaveRequestTrigger` = `100%`
  - `LeaveHomeController` = `59%`

本轮新增测试重点：

- `LeaveHomeControllerTest`
  - 覆盖首页可选假种接口仅返回“启用且当前账本支持”的 definition 记录
  - 覆盖首页直接创建 Draft 申请时，自动写入 `Leave_Type_Definition__c / Leave_Type_Code__c / Leave_Type_Name__c`
  - 覆盖对尚未开放自助建单的 richer 假种进行阻断，避免用户在首页创建不可提交的申请
- `LeaveServiceTest`
  - 覆盖删除 `Leave_Type__c` 后，申请/审批/扣减链路通过 `Leave_Type_Definition__c + Leave_Type_Code__c + Leave_Type_Name__c` 继续运行
  - 覆盖取消/撤回、跨年余额校验、自动批准、经理审批流与 HR 审批流在新模型下持续通过
- `LeaveSetupInitializationServiceTest`
  - 覆盖丰富假种模板初始化，验证 `ANNUAL / SICK / PERSONAL` 核心类型与婚假、产假、陪产假、丧假、工伤假、调休假、学习假等预置策略
  - 覆盖年度余额初始化，对缺失余额创建默认额度，对已有余额保持幂等
  - 覆盖 `overwriteExistingBalances=true` 时的批量重置行为
  - 覆盖 `LeaveSetupInitializationJob` 手动 enqueue 后的完整执行
- `LeaveApprovalRoutingServiceTest`
  - 覆盖 `HR Only`
  - 覆盖 `Configurable` 升级到 `Custom Queue`
  - 覆盖缺失直属经理时的异常分支
  - 覆盖审批目标与审批来源回退分支
  - 覆盖 `Approval_Group_Key__c` 到 Queue / Group 首个用户成员的解析
  - 覆盖嵌套 Group 递归解析
  - 覆盖直接 `User Id` 目标解析
- `LeaveHomeControllerTest`
  - 覆盖角色识别在无 `Leave_Manager` 权限集时通过直属下属关系兜底识别经理
  - 覆盖 HR 待审查询接口仅返回 `Pending_HR_Approval` 记录
- `LeaveApprovalHistoryServiceTest`
  - 覆盖自动批准场景下的 `Submit / Submitted` 与 `Submit / Approved` 双历史
  - 覆盖 `LeaveExpiryBatch` 自动取消后的 `Cancellation / Cancelled` 历史快照
- `LeaveServiceTest`
  - 覆盖 `submitLeave()` 在 `Manager Then HR` 策略下真实调用 `Approval.process` 并创建 `ProcessInstance`
  - 覆盖 `submitLeave()` 在 `HR Only` 策略下跳过 `Approval.process` 并写入提交历史
  - 覆盖 `submitLeave()` 在 `Auto Approve` 策略下跳过审批流并写入双历史、自动扣减余额
  - 覆盖草稿取消与已发起审批后的 recall/cancel 闭环
  - 覆盖 `approveLeave()` 在经理审批后升级 HR 时不应提前扣减余额
  - 覆盖 `rejectLeave()` 的 HR 驳回历史
  - 覆盖 `rejectLeave()` 非法状态异常
  - 覆盖 `approveLeave()` 非法状态异常
  - 覆盖 `validateBalance()` 无余额与已有占用场景
  - 覆盖跨年申请缺失目标年度余额场景
  - 覆盖 `hasOverlappingDates()` 的正向、草稿排除、自身排除场景
  - 覆盖 `Sick / Personal` 扣减分支

本轮主线补通：

- `submitLeave()` 的 Manager 审批流正向集成测试已补齐并通过
  - 已修复 `approvalProcesses/Leave_Request__c.Leave_Request_Approval.approvalProcess-meta.xml` 的 metadata schema
  - 已新增 `workflows/Leave_Request__c.workflow-meta.xml` 承载审批动作引用的状态更新
  - manager-path 现已能真实进入 `Approval.process` 并生成 `ProcessInstance`

本轮顺带修复：

- 修复 `LeaveService` 与 `LeaveRequestHandler` 同时写审批历史导致的重复历史问题
- 当前显式审批动作会保留真实审批人和审批意见，触发器侧不会再重复写入同一条历史
- 修复经理审批通过后升级到 HR 时提前触发余额扣减的问题，现仅在申请真正进入最终 `Approved` 状态后扣减余额
- 为 `rejectLeave()` 增加非法状态保护，避免草稿等非审批态请求被直接驳回
- 修复 `submitLeave()` 对新审批策略的兼容问题：
  - `Pending_Manager_Approval` 时才调用 `Approval.process`
  - `HR Only` 与 `Auto Approve` 策略下不再错误强依赖审批流程元数据
  - `submitLeave()` 现在基于更新后的真实快照状态写历史，避免旧内存状态导致审批目标与历史失真
- 修复审批流程 metadata 主链路：
  - `ApprovalProcess` 改为 org 可部署的新版 schema
  - `WorkflowFieldUpdate` 从审批流文件拆分到 `Workflow` metadata
  - manager-path 的审批流定义现已成功部署到 `test` org
- 接入 Queue / Group 真实成员解析：
  - `Approval_Group_Key__c` 不再只作为快照字符串，现可解析到真实 `User`
  - 支持按 `Group.DeveloperName / Name` 查找审批目标
  - 支持嵌套 `GroupMember` 递归下钻到首个用户成员
  - 已接入 `Submit` 与 `HR_Approval` 场景的审批人解析
- 接入首页动作工作台闭环：
  - `LeaveHomeController` 新增 `submit / approve / reject / cancel` 的 `@AuraEnabled` 动作入口
  - `LeaveHomeController` 新增 `getHrPendingApprovals()`，不再只给 HR 看全量列表
  - `leaveHome` LWC 新增员工提交/取消、经理审批/驳回、HR 审批/驳回按钮
  - 角色识别新增“直属下属关系兜底”，降低对缺失权限集元数据的依赖
  - `LeaveService` 新增 `cancelLeave()`，支持撤回待审批申请并写入 `Cancellation` 历史
- 接入初始化配置能力：
  - 新增 `LeaveSetupInitializationService`，支持幂等初始化默认假种模板与年度余额
  - 新增 `LeaveSetupInitializationJob`，支持通过匿名 Apex 手动 enqueue 一键执行初始化
  - 默认会预置 `Annual / Sick / Personal / Comp Off / Marriage / Maternity / Paternity / Bereavement / Work Injury / Study` 十类假种策略
  - 默认会为全部激活标准用户初始化当年 `Annual=15 / Sick=10 / Personal=5` 的基础余额
- 删除旧假种字段主线：
  - 已删除 `Leave_Request__c.Leave_Type__c` 本体及其布局、审批页引用
  - `LeaveRequestHandler` 已改为从 `Leave_Type_Definition__c` 直接生成 `Leave_Type_Code__c / Leave_Type_Name__c / Policy_Version__c`
  - `LeaveService` 已改为基于 `Leave_Type_Code__c` 做余额校验与扣减，不再依赖旧 picklist
  - 首页与员工首页查询均改为展示 `Leave_Type_Name__c`
- 收口首页新建入口：
  - `leaveHome` 已成为唯一保留的首页建单入口，`leaveEmployeeHome / EmployeeLeaveController` 已从仓库删除
  - 新增 `LeaveHomeController.getAvailableLeaveTypes()`，由后端统一下发可自助建单的启用假种
  - 新增 `LeaveHomeController.createLeaveRequest()`，直接按 `Leave_Type_Definition__c` 创建 Draft 申请
  - 当前首页新建入口仅开放 `ANNUAL / SICK / PERSONAL` 三类已接入余额账本的假种，避免 richer 假种先被创建但无法闭环
  - `leaveHome` 已修复首页列表刷新链路：员工列表、经理列表、HR 列表统一改为 Promise 回刷；`My Leave Requests` 新建后会立即重查并更新列表
  - `leaveHome` 已补空态提示，避免空数组场景因真假值判断导致页面表现异常

---

## 3. 当前系统状态判断

### 3.1 已经具备的能力

- 支持基础请假申请与审批
- 支持年假结转到次年并设置过期日
- 支持通过假种配置对象描述部分制度规则
- 支持在申请单中保留假种和策略快照
- 支持将跨年请假按自然年拆分为多个 Segment
- 支持跨年请假按年度余额分别校验与扣减
- 支持按假种审批策略驱动提交状态流转
- 支持配置自动批准、经理审批、经理后 HR 审批、HR 直审
- 支持统一写入审批历史，并保留审批模式与审批目标快照
- 支持基于 `Approval_Group_Key__c` 解析 Queue / Group 的真实用户成员，用于审批历史与审批来源落点
- 支持首页直接完成提交、经理审批、HR 审批与取消/撤回动作，不再只停留在查询看板
- 支持通过手动调用 job / service 初始化默认假种配置与年度余额
- 支持申请单直接以 `Leave_Type_Definition__c` 作为唯一假种来源，旧 `Leave_Type__c` 已清除
- 支持首页直接以 `Leave_Type_Definition__c` 创建 Draft 申请，不再依赖标准页手工选 lookup
- 支持 `Leave_Balance_Line__c + Leave_Balance_Transaction__c` 新账本主链路：
  - 提交校验切到按 `Leave_Request_Segment__c` 分年度校验
  - 提交时写入 `Reserve`
  - 最终批准时写入 `Consume`
  - 驳回 / 取消时写入 `Release`
  - 年假结转写入 `Carryover`
  - 结转过期写入 `Expire`
- 支持首页余额查询基于账本明细汇总返回，而不是直接绑定旧 `Leave_Balance__c` 固定字段
- 支持旧余额头到新账本明细的按需补建，并将新账本汇总回写到 `Leave_Balance__c` 作为兼容层

### 3.2 仍处于过渡阶段的部分

- 运行时主模型已切到 `Leave_Balance_Line__c / Leave_Balance_Transaction__c`，但 `Leave_Balance__c` 仍作为兼容汇总头保留，尚未彻底退役
- 当前余额账本主链路仍显式收口在 `ANNUAL / SICK / PERSONAL` 三类核心编码，其他 richer 假种已可配置但尚未映射到通用余额初始化与页面展示
- 跨年请假已完成自然年拆分，但尚未扩展到 `Hire Anniversary` 等非自然年周期
- 审批策略配置化已接入状态流转、历史快照与 Queue / Group 成员解析，但仍未扩展到多成员轮询/负载均衡分派
- 首页动作工作台已可运行，但 LWC 仍未挂到正式 FlexiPage / App Home，当前主要完成的是能力闭环，不是最终承载页收口

---

## 4. 当前建议阶段划分

### 第一阶段：兼容扩展

目标：

- 不推翻现有对象和审批主流程
- 先补充可扩展字段、配置对象、服务骨架
- 让年假结转、过期和基本策略读取先跑起来

状态：

- 已基本完成

### 第二阶段：主模型切换

目标：

- 将余额与扣减逐步迁移到新明细模型
- 将假种扩展能力从固定字段切到配置驱动
- 将跨年拆分和审批策略配置化切入统一服务层

状态：

- 已完成主链路切换并通过核心回归
- 仍保留 legacy 汇总头作为兼容层

### 第三阶段：收敛遗留

目标：

- 弱化旧固定字段职责
- 统一报表、审计、审批和余额口径
- 清理兼容过渡逻辑

状态：

- 尚未开始

---

## 5. 下一步优先任务建议

建议按以下顺序继续推进：

1. 落地 `Leave_Request_Segment__c`，实现跨年请假拆分扣减
   - 状态：已完成自然年拆分版本
2. 落地审批策略解析服务，将不同假种审批模式切到配置驱动
   - 状态：已完成提交路由、经理后升级 HR、审批来源解析与审批历史快照的基础闭环
3. 落地 `Leave_Balance_Line__c` 与 `Leave_Balance_Transaction__c` 的正式写入
   - 状态：已完成主链路切换并已在 org 回归通过
4. 将报表指标逐步切换到新账本模型
   - 状态：未开始
5. 最后收敛旧字段模型
   - 状态：进行中，当前仍保留 `Leave_Balance__c` 兼容汇总

---

## 6. 当前风险提示

- 设计已较完整，但实现仍处于“新旧模型并存”的过渡期
- 如果过早扩大改造范围，容易影响现有审批链路稳定性
- 若先做大规模重构而不保留过渡层，历史数据解释和回归验证成本会显著上升
- 报表若继续长期依赖旧余额字段，将无法完整表达流水级审计信息；当前应优先逐步切到 `Leave_Balance_Line__c / Leave_Balance_Transaction__c`
- 当前跨年拆分已按自然年生效，但还未覆盖按入职周年等自定义余额周期拆分
- HR/Queue/上级经理等审批目标虽已快照，但还未继续下钻到 Queue / Group 成员级别解析

---

## 7. 当前结论

当前项目最合理的推进方式是：

- 设计先完整
- 实现分阶段
- 每完成一层能力，就补对应测试与报表口径
- 已完成“跨年请假自然年拆分 + 分年度校验扣减”这一阶段性里程碑
- 已完成“审批策略驱动提交状态流转 + 经理审批后升级 HR”的阶段性里程碑
- 已完成“审批来源统一解析 + 审批历史快照统一写入”的阶段性里程碑
- 已完成“余额主链路切换到新账本模型 + legacy 兼容汇总回写”的阶段性里程碑

这能在保证业务连续性的前提下，逐步把系统从“基础请假审批系统”升级为“可配置、可审计、可长期演进的请假制度平台”。
