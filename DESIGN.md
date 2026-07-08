# 请假审批系统设计（Salesforce）

## 1. 概述

请假审批系统构建在 Salesforce 平台之上，用于管理员工请假申请、审批流程、假期余额跟踪、审计记录与报表分析。

系统支持以下核心能力：

- 员工提交请假申请
- 直属经理审批
- HR 全量可见与审计追踪
- 自动校验并扣减假期余额
- 报表与分析

---

## 2. 架构概览

系统采用标准 Salesforce 分层架构：

界面层（LWC / Flow / Lightning Pages）  
↓  
流程层（Approval Process / Flow / Apex）  
↓  
服务层（Apex Services）  
↓  
数据层（Custom Objects）  
↓  
安全层（Profile + Permission Set + OWD + Sharing）

---

## 3. 设计原则

- 优先使用 Salesforce 标准审批与安全能力，只有在 Flow 无法安全承载时才引入 Apex。
- 审批路由必须可确定、可追踪，一级审批人必须来自单一可信来源。
- 假期余额校验与扣减逻辑必须和请假类型设计保持一致。
- 禁止硬编码 ID、RecordTypeId、用户名和角色名。
- HR 可见性必须覆盖记录全生命周期，而不是只覆盖 `Submitted` 状态。
- 从设计阶段就考虑报表、审计和后续扩展能力。

---

## 4. 数据模型

## 4.1 核心对象

系统使用以下 3 个核心自定义对象：

1. `Leave_Request__c`
   - 请假申请主交易对象。
2. `Leave_Balance__c`
   - 员工按年度维护的假期余额对象。
3. `Leave_Approval_History__c`
   - 自定义审批操作审计对象。

这 3 个对象都属于基线设计的一部分，不再视为可选占位对象。

---

## 4.2 Leave_Request__c（核心对象）

表示员工发起的一条请假申请。

### 对象定义

- 标签：Leave Request
- API 名称：`Leave_Request__c`
- Name 字段类型：Auto Number
- 编号格式：`LEAVE-{0000}`
- 所有权：由提交申请的员工拥有记录

### 字段设计

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| Name | Auto Number | 是 | 请假申请单号 |
| Employee__c | Lookup(User) | 是 | 申请人 |
| Manager__c | Lookup(User) | 是 | 提交时快照保存的直属经理 |
| Start_Date__c | Date | 是 | 请假开始日期 |
| End_Date__c | Date | 是 | 请假结束日期 |
| Days__c | Number(5,2) | 是 | 请假天数 |
| Leave_Type__c | Picklist | 是 | Annual / Sick / Personal |
| Status__c | Picklist | 是 | Draft / Submitted / Pending_Manager_Approval / Pending_HR_Approval / Approved / Rejected / Cancelled |
| Reason__c | Long Text Area(1000) | 否 | 请假原因 |
| Submitted_Time__c | DateTime | 否 | 提交时间 |
| Balance_Deducted__c | Checkbox | 是 | 防止重复扣减余额 |

### 说明

- `Manager__c` 为快照字段，在提交申请时从 `Employee.ManagerId` 写入。
- 审批过程中的一级审批人必须使用 `Manager__c`，而不是实时读取最新组织层级。
- `Status__c` 进行了细化，用于明确区分经理审批阶段与 HR 审批阶段。

---

## 4.3 Leave_Balance__c

用于按员工、按年度维护假期余额。

### 对象定义

- 标签：Leave Balance
- API 名称：`Leave_Balance__c`
- Name 字段类型：Auto Number
- 编号格式：`BAL-{0000}`

### 字段设计

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| Name | Auto Number | 是 | 余额记录编号 |
| User__c | Lookup(User) | 是 | 员工 |
| Year__c | Number(4,0) | 是 | 自然年度 |
| Annual_Leave__c | Number(5,2) | 是 | 年假剩余额度 |
| Sick_Leave__c | Number(5,2) | 是 | 病假剩余额度 |
| Personal_Leave__c | Number(5,2) | 是 | 事假剩余额度 |
| Unique_Key__c | Text(50), Unique, External ID | 是 | 业务唯一键，例如 `005xx0000012345-2026` |

### 说明

- 当前余额设计已经和请假类型 `Annual / Sick / Personal` 保持一致。
- `Unique_Key__c` 用于保证“同一员工同一年只有一条余额记录”。
- 未来进行余额初始化、年结转或累计规则扩展时，可以稳定定位唯一记录。

---

## 4.4 Leave_Approval_History__c

用于记录审批过程中的自定义审计轨迹。

### 对象定义

- 标签：Leave Approval History
- API 名称：`Leave_Approval_History__c`
- 父子关系：`Leave_Request__c` 的 Master-Detail 子对象

### 字段设计

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| Name | Auto Number | 是 | 审批历史编号 |
| Leave_Request__c | Master-Detail(Leave_Request__c) | 是 | 所属请假申请 |
| Approver__c | Lookup(User) | 是 | 审批人或操作人 |
| Stage__c | Picklist | 是 | Submit / Manager Approval / HR Approval / Cancellation |
| Action__c | Picklist | 是 | Submitted / Approved / Rejected / Cancelled |
| Comments__c | Long Text Area(1000) | 否 | 审批意见 |
| Action_Time__c | DateTime | 是 | 操作时间 |

### 说明

- 采用自定义历史对象，是因为标准审批历史不足以满足灵活报表、导出和扩展审计要求。
- 该对象完全依附于 `Leave_Request__c`，因此优先使用 `Master-Detail`，而不是松散的 `Lookup`。

---

## 4.5 关系设计

### `Leave_Request__c`

- `Employee__c` → `User`，使用 `Lookup`
- `Manager__c` → `User`，使用 `Lookup`

原因：

- 请假申请属于业务用户，但不适合与 `User` 建立主从关系。
- 经理关系需要保存为提交时的审批快照，而不是动态层级关系。

### `Leave_Balance__c`

- `User__c` → `User`，使用 `Lookup`

原因：

- 假期余额逻辑上关联员工，但仍需要独立管理，以便后续做年度初始化、对账和调整。

### `Leave_Approval_History__c`

- `Leave_Request__c` → `Leave_Request__c`，使用 `Master-Detail`

原因：

- 审批历史不能脱离请假申请独立存在。
- 如果组织允许管理员删除请假申请，则对应审计子记录可以随父对象一致管理。

---

## 5. 安全设计

## 5.1 对象级权限设计

### 员工 Profile

- `Leave_Request__c`：可创建、可读、可编辑自己的草稿或可取消记录
- `Leave_Balance__c`：仅可读自己的余额记录
- `Leave_Approval_History__c`：仅可读自己有权限访问的相关审批历史
- 对交易类记录不授予 Delete 权限

### 经理 Permission Set

- 可读取下属请假申请
- 可审批或驳回分配给自己的申请
- 可访问经理视角报表与团队日历

### HR Permission Set

- 可读取全部请假申请
- 可读取全部余额记录
- 可读取全部审批历史
- 当启用二级审批时，可处理 HR 阶段审批
- 可访问报表与导出功能

---

## 5.2 组织范围默认共享（OWD）

- `Leave_Request__c` = Private
- `Leave_Balance__c` = Private
- `Leave_Approval_History__c` = Controlled by Parent

原因：

- 保护敏感 HR 数据
- 遵循最小权限原则
- 审批历史跟随主申请记录继承可见性

---

## 5.3 角色层级设计

CEO  
└── HR Director  
└── Business Director  
└── Manager  
└── Employee

规则：

- 经理可通过层级查看下属请假申请
- 总监可查看本层级下属记录
- HR 可见性不能仅依赖角色层级

---

## 5.4 共享规则

- HR Public Group：对所有 `Leave_Request__c` 授予读取权限
- HR Public Group：对所有 `Leave_Balance__c` 授予读取权限
- HR 核心可见性不依赖状态条件共享

原因：

- HR 需要对 `Submitted`、`Approved`、`Rejected`、`Cancelled` 全状态保持可见
- 如果只在 `Submitted` 状态共享，会破坏审计与报表完整性

---

## 5.5 审批人来源单一规则

- 第一级审批人必须来源于 `Leave_Request__c.Manager__c`
- `Manager__c` 在提交时由 `Employee.ManagerId` 一次性写入
- 提交后如果员工直属经理发生变化，不影响已在途申请
- 第二级 HR 审批人如果启用，必须来自可配置的 HR Group 或 Queue，不能硬编码到具体用户

---

## 6. 业务流程设计

## 6.1 请假提交流程

推荐实现方式：Screen Flow

步骤：

1. 员工选择请假类型
2. 员工输入开始日期与结束日期
3. 系统校验日期范围
4. 系统计算请假天数
5. 系统将当前直属经理写入 `Manager__c`
6. 系统将状态设置为 `Pending_Manager_Approval`
7. 系统记录 `Submitted_Time__c`

---

## 6.2 审批流程

### 第一步：经理审批

- 审批人 = `Manager__c`
- 审批结果：
  - 同意 → `Pending_HR_Approval` 或直接 `Approved`
  - 驳回 → `Rejected`

### 第二步：HR 审批

- 仅在业务策略要求二级审批时启用
- 审批人来源 = 可配置的 HR Group / Queue
- 审批结果：
  - 同意 → `Approved`
  - 驳回 → `Rejected`

### 审批历史写入

- 每一步审批都写入一条 `Leave_Approval_History__c`
- 审批意见保存在 `Comments__c`

---

## 6.3 余额校验与扣减

规则：

- 在最终审批通过前必须校验余额是否充足
- 假期余额只能扣减一次
- 对于驳回或取消的申请，不得扣减余额

行为：

- 通过 `Unique_Key__c` 查询 `Leave_Balance__c`
- 根据 `Leave_Type__c` 映射到对应余额字段
- 更新对应的余额值
- 成功扣减后将 `Balance_Deducted__c` 置为 `true`

---

## 7. 自动化设计

## 7.1 Record-Triggered Flow

### Before Save

- 校验 `End_Date__c >= Start_Date__c`
- 计算 `Days__c`
- 在需要时阻止已审批记录被非法修改

### After Save

- 在提交申请后通知直属经理
- 在提交时创建初始 `Leave_Approval_History__c`
- 创建审批工作项或触发审批路由

---

## 7.2 Apex Services

对于跨对象、可复用、或 Flow 不适合安全实现的逻辑，使用 Apex。

推荐服务类：

`LeaveService`

- `validateLeave()`
- `submitLeave()`
- `approveLeave()`
- `rejectLeave()`
- `deductBalance()`

---

## 7.3 Trigger 设计

Trigger 使用必须保持最小化。

仅在以下场景允许使用 Trigger：

- 需要批量安全处理的跨对象校验
- 可复用的余额扣减编排逻辑
- Flow 无法保证一致性的场景

推荐模式：

Trigger → Handler → Service Layer

---

## 8. 校验规则设计

以下规则属于系统基线规则：

- 结束日期必须大于或等于开始日期
- 请假天数必须大于 0
- 同一员工不能存在日期重叠的有效请假申请
- 同一申请不得重复提交
- 当对应假期余额不足时，不允许最终审批通过

### 日期重叠校验范围

重叠校验应检查以下条件：

- 同一个 `Employee__c`
- 日期范围存在交集
- 仅针对有效状态：
  - `Submitted`
  - `Pending_Manager_Approval`
  - `Pending_HR_Approval`
  - `Approved`

---

## 9. 界面设计

## 9.1 员工界面

组件：

- My Leave Requests
- New Leave Request button
- My Leave Balance card

---

## 9.2 经理界面

组件：

- Pending Approvals
- Team Leave Calendar
- Team Leave Overview

---

## 9.3 HR 界面

组件：

- All Leave Requests
- All Leave Balances
- Audit History view
- Reporting Dashboard
- Export Functionality

---

## 10. App 承载设计

## 10.1 设计结论

建议为请假审批系统创建独立的 Lightning App 来承载功能，但 App 只负责导航入口、页面组织和角色体验，不负责真正的权限控制。

权限控制仍然必须由以下能力承担：

- Profile
- Permission Set
- OWD
- Sharing Rules
- Dynamic Visibility

App 的核心价值是：

- 为员工、经理、HR 提供统一业务入口
- 把对象、列表、报表、审批页组织成完整业务工作台
- 降低用户从全局导航中寻找功能的成本
- 为后续扩展 LWC、Dashboard、Calendar 提供稳定承载位置

---

## 10.2 推荐 App 方案

推荐分两阶段建设：

### 第一阶段

先建设一个统一 App：

- App Label: Leave Management
- API Name: `Leave_Management`

适用原因：

- 上线速度快
- 便于先完成对象、流程、审批与页面配置
- 通过权限和动态可见性即可区分员工、经理和 HR 的界面内容

### 第二阶段

若后续角色差异继续扩大，可拆分为两个 App：

- `Leave_Employee`
  - 面向员工
- `Leave_Manager_HR`
  - 面向经理与 HR

适用条件：

- 菜单差异明显
- 首页组件差异明显
- 需要简化员工侧入口
- 经理与 HR 的工作台已经演变成独立业务场景

---

## 10.3 第一阶段统一 App 导航建议

`Leave Management` 建议包含以下导航项：

- Home
- Leave Requests
- My Leave Requests
- My Leave Balances
- Pending Approvals
- Team Leave Calendar
- Leave Approval Histories
- Reports
- Dashboards

设计原则：

- 员工高频入口优先靠前
- 审批入口必须在经理视角中明显可见
- HR 台账与报表入口必须稳定存在
- 不把所有对象 Tab 原样暴露给所有角色

---

## 10.4 角色首页设计

### 员工首页

建议组件：

- 我的请假申请列表
- 新建请假快捷按钮
- 我的假期余额卡片
- 待处理提醒或最近记录

### 经理首页

建议组件：

- 待我审批列表
- 团队请假日历
- 团队请假概览
- 异常申请提醒

### HR 首页

建议组件：

- 全量请假申请列表
- 审批历史审计卡片
- 假期余额监控
- 统计报表入口
- 导出入口

---

## 10.5 页面分配策略

建议通过 Lightning App Builder 做页面分配，而不是为同一对象重复创建过多页面。

推荐分配方式：

- App Default Page
  - 统一 App 默认首页
- App + Profile / App + Record Type Assignment
  - 根据角色差异分配不同首页
- Dynamic Visibility
  - 在同一页面中按权限隐藏或显示组件

适用原则：

- 角色差异不大时，优先用一套页面 + 动态可见性
- 角色差异明显时，再拆分独立首页
- 不要把权限控制寄托在 App 是否可见上

---

## 10.6 与当前设计的映射关系

当前设计中的界面模块可以直接映射到 App：

- 员工界面
  - `My Leave Requests`
  - `New Leave Request`
  - `My Leave Balance`
- 经理界面
  - `Pending Approvals`
  - `Team Leave Calendar`
  - `Team Leave Overview`
- HR 界面
  - `All Leave Requests`
  - `All Leave Balances`
  - `Audit History`
  - `Reporting Dashboard`

这意味着 App 设计不需要推翻现有 UI 方案，而是为现有 UI 提供标准化承载容器。

---

## 10.7 风险与约束

- App 不是权限模型，不能替代 Profile / Permission Set / Sharing
- 不建议一开始就拆出过多 App，避免导航碎片化
- 不建议让员工直接看到 HR 级对象台账入口
- 不建议把审批逻辑写进 App 层，App 只负责入口承载

---

## 11. 报表与分析

报表设计不能只停留在“能看到多少条申请”，而必须支撑制度解释、管理决策、HR 对账、审计追踪和后续优化。

### 11.1 报表设计目标

报表体系应覆盖以下目标：

- 为管理层提供请假总量、审批效率、积压风险和制度执行情况。
- 为 HR 提供余额对账、结转监控、失效监控和异常申请识别。
- 为经理提供团队请假分布、未来排班风险和审批负载。
- 为审计提供申请、审批、余额流水和规则版本的一致性追踪能力。

---

### 11.2 报表主题域

推荐将报表分为 5 个主题域：

1. 请假申请主题
2. 审批效率主题
3. 余额与结转主题
4. 制度执行与异常主题
5. 管理驾驶舱主题

---

### 11.3 请假申请主题

用于观察员工请假行为、组织负载和请假结构。

标准报表建议包括：

- 月度请假使用情况
- 部门请假统计
- 按假种统计申请量
- 员工请假频次排行
- 跨年请假申请统计
- 未来 30 天请假排期视图

关键指标：

| 指标 | 说明 |
|------|------|
| Leave_Request_Count | 请假申请总数 |
| Approved_Days | 已审批通过天数 |
| Pending_Days | 待审批天数 |
| Cross_Year_Request_Count | 跨年申请数量 |
| Avg_Days_Per_Request | 单笔申请平均请假天数 |

设计说明：

- 跨年请假应按主单和 Segment 两个口径分别统计。
- 面向管理层展示时，优先展示趋势与风险，不应只展示原始明细。

---

### 11.4 审批效率主题

用于衡量审批链路是否顺畅，以及是否存在管理瓶颈。

标准报表建议包括：

- 审批周期时长
- 经理审批时长分布
- HR 审批时长分布
- 待审批积压情况
- 按假种统计驳回率
- 审批节点转化漏斗

关键指标：

| 指标 | 说明 |
|------|------|
| Avg_Approval_Duration_Hours | 平均审批时长 |
| Manager_Approval_Duration_Hours | 经理审批平均时长 |
| HR_Approval_Duration_Hours | HR 审批平均时长 |
| Rejection_Rate | 驳回率 |
| Pending_Backlog_Count | 当前积压待审数量 |
| Over_SLA_Count | 超过审批 SLA 的申请数量 |

设计说明：

- 审批时长应至少拆成“提交到经理审批”“经理通过到 HR 审批”“最终审批完成”三个阶段。
- 不同假种审批模式不同，报表必须能按 `Approval_Mode` 或审批阶段进行切片。

---

### 11.5 余额与结转主题

该主题是当前系统增强设计中的重点，用于解释“额度从哪里来、用到哪里去、为什么会过期”。

标准报表建议包括：

- 假期余额趋势
- 年假制度授予额度统计
- 年假结转额度统计
- 结转额度实际使用情况
- 结转额度过期失效统计
- 年度余额初始化完成率

关键指标：

| 指标 | 说明 |
|------|------|
| Granted_By_Policy_Total | 按制度授予的总额度 |
| Carryover_Total | 结转总额度 |
| Carryover_Used_Total | 已使用结转额度 |
| Carryover_Expired_Total | 已过期结转额度 |
| Current_Balance_Total | 当前可用余额 |
| Reset_Completed_Count | 已完成年度重置的员工数量 |

设计说明：

- 报表必须明确区分“制度授予额度”“结转额度”“人工调整额度”。
- 若后续引入 `Leave_Balance_Line__c` 与 `Leave_Balance_Transaction__c`，则该主题应优先基于余额明细和余额流水构建。
- 若仍处于兼容阶段，可暂时在 `Leave_Balance__c` 上提供过渡报表，但这不应成为长期目标模型。

---

### 11.6 制度执行与异常主题

用于识别制度执行偏差、脏数据和潜在风险。

标准报表建议包括：

- 余额不足被阻止的申请统计
- 重复提交或重叠日期申请统计
- 停用假种仍被引用的历史申请统计
- 年度重置失败或跳过记录统计
- 工龄递增授予封顶分布
- 人工调整额度异常排行

关键指标：

| 指标 | 说明 |
|------|------|
| Validation_Failure_Count | 校验失败次数 |
| Overlap_Request_Count | 日期重叠申请数量 |
| Inactive_Type_Request_Count | 命中停用假种的申请数量 |
| Manual_Adjustment_Total | 人工调整总额度 |
| Reset_Error_Count | 年度重置异常数量 |
| Max_Entitlement_Reached_Count | 达到年假封顶人数 |

设计说明：

- 该主题应服务于 HR 治理和系统运维，而不仅仅是业务展示。
- 任何“重复执行”“规则版本切换”“跨年拆分失败”都应有可监控口径。

---

### 11.7 管理驾驶舱

建议为管理层和 HR 分别建设 Dashboard，而不是只提供原始报表列表。

#### 管理层 Dashboard

推荐组件：

- 本月请假总天数
- 待审批积压量
- 审批平均时长趋势
- 未来 30 天团队请假热力分布
- 结转额度即将过期人数
- 假种使用结构占比

#### HR Dashboard

推荐组件：

- 年度授予完成率
- 结转额度使用与过期情况
- 工龄递增授予分布
- 异常申请数量
- 人工调整额度排行
- 审批 SLA 违约明细

设计说明：

- Dashboard 应优先服务管理决策，而不是堆叠过多明细表。
- 对高频关注项，建议提供月度趋势和异常 Top N 两种呈现方式。

---

### 11.8 指标口径统一规则

为避免不同报表使用不同口径，必须统一以下规则：

- 请假总量默认以“审批通过的申请”统计，除非明确标识为“全部申请”。
- 审批时长默认使用业务处理时间，不混入系统创建时间误差。
- 跨年申请按主单统计时记 1 笔，按额度消耗统计时按 Segment 拆分。
- 年假可用额度必须拆分为“制度授予”“结转”“人工调整”三部分。
- 结转过期统计必须以实际过期流水为准，而不是用当前剩余额度反推。
- 工龄递增统计必须以当期授予时点的工龄快照为准，而不是用当前工龄回算历史。

---

### 11.9 数据源建议

建议报表数据源按以下层级建设：

- 第一层：`Leave_Request__c`
- 第二层：`Leave_Approval_History__c`
- 第三层：`Leave_Balance__c`
- 第四层：`Leave_Balance_Line__c`
- 第五层：`Leave_Balance_Transaction__c`
- 第六层：`Leave_Request_Segment__c`

建设原则：

- 初期可用 `Leave_Request__c + Leave_Balance__c + Leave_Approval_History__c` 搭建基础报表。
- 中长期必须把核心指标迁移到 `Leave_Balance_Line__c / Leave_Balance_Transaction__c / Leave_Request_Segment__c`，否则难以准确表达结转、工龄递增和跨年拆分。

---

### 11.10 实施优先级

推荐分三批建设：

#### 第一批

- 月度请假使用情况
- 部门请假统计
- 审批周期时长
- 待审批积压情况

#### 第二批

- 假期余额趋势
- 结转额度使用与过期统计
- 按假种统计驳回率
- 年度授予完成率

#### 第三批

- 工龄递增授予分析
- 跨年 Segment 用假分析
- 人工调整异常分析
- 规则版本影响分析

---

## 12. 集成设计（可选）

可扩展集成方向：

- 薪资系统，用于同步请假扣减结果
- HRMS 系统，用于同步员工主数据
- 邮件 / Slack 通知系统

集成约束：

- 禁止硬编码接口用户或记录 ID
- 使用配置型元数据控制集成开关和路由

---

## 13. 性能设计

- Apex 必须支持批量处理
- 禁止在循环中写 SOQL
- 禁止在循环中写 DML
- 使用选择性查询
- 对重型审批后逻辑采用异步处理

---

## 14. 未来扩展

- 基于 AI 的审批建议
- 动态审批路由引擎
- 多公司支持
- 移动端优先体验优化
- 预测性请假分析
- 基于元数据驱动的请假类型策略模型

---

## 15. 扩展性增强设计

当前设计已经满足基线请假审批需求，但如果系统要支持“请假类型可持续扩展”“按年重置与结转余额”“不同假种走不同审批策略”，则需要从固定字段模型升级为可配置、可审计、可幂等的设计。

---

## 15.1 当前扩展性瓶颈

基于当前设计与现有仓库实现，可以识别出以下扩展性约束：

- `Leave_Request__c.Leave_Type__c` 采用固定 Picklist，新增假种需要改元数据、改校验、改测试。
- `Leave_Balance__c` 使用 `Annual_Leave__c / Sick_Leave__c / Personal_Leave__c` 固定字段存储余额，每新增一种假期类型都需要新增字段并修改服务逻辑。
- 余额计算当前天然绑定自然年，服务层普遍按“当前系统年份”取余额，而不是按申请归属年度或策略年度取余额。
- 年度重置、结转、过期失效尚未形成标准编排能力，无法稳定支持“年假每年清零但可结转 5 天”“病假不清零”“婚假入职当年一次性发放”等差异化规则。
- 审批路径目前主要围绕固定状态设计，尚未支持“某些假种必须 HR 二审、某些假种仅经理审批、某些假种超过阈值需升级审批”。
- 历史申请对假种规则缺少版本快照保护，若后续直接修改假种规则，容易影响历史单据解释与审计口径。

---

## 15.2 扩展目标

增强后的设计应满足以下目标：

- 新增请假类型时，不再新增余额字段，也不应大面积修改 Apex `if/else`。
- 余额模型必须支持“按员工 + 按年度 + 按假种”管理，并可追溯每一次授予、占用、扣减、释放、结转和失效。
- 年度重置必须支持幂等执行，避免调度重复执行造成重复发放或重复结转。
- 历史申请必须保留规则快照，不能因为后续修改假种定义而影响历史口径。
- 跨年请假、补录请假、撤回审批、驳回释放余额等边界场景必须闭环。

---

## 15.3 配置层增强

推荐新增假种配置对象：

### `Leave_Type_Definition__c`

用于定义可扩展的请假类型目录，由 HR 或系统管理员维护。

建议字段：

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| Name | Text | 是 | 假种名称 |
| Type_Code__c | Text(40), Unique | 是 | 稳定业务编码，例如 `ANNUAL` / `SICK` / `MARRIAGE` |
| Unit__c | Picklist | 是 | Day / Hour |
| Is_Active__c | Checkbox | 是 | 是否启用 |
| Requires_HR_Approval__c | Checkbox | 是 | 是否要求 HR 二级审批 |
| Allow_Negative_Balance__c | Checkbox | 是 | 是否允许透支 |
| Default_Entitlement__c | Number(8,2) | 否 | 默认授予额度 |
| Accrual_Mode__c | Picklist | 是 | Fixed / Seniority |
| Base_Entitlement__c | Number(8,2) | 否 | 基础额度，例如基础年假 5 天 |
| Accrual_Per_Year__c | Number(5,2) | 否 | 每满 1 个服务年限增加的额度，例如每年 +1 天 |
| Accrual_Max_Days__c | Number(5,2) | 否 | 工龄累计后的最大总额度上限 |
| Service_Year_Basis__c | Picklist | 是 | Calendar Year / Hire Anniversary |
| Eligibility_Start_Months__c | Number(3,0) | 否 | 需满多少个月才开始获得该假种资格 |
| Reset_Mode__c | Picklist | 是 | Calendar Year / Hire Anniversary / No Reset |
| Carryover_Mode__c | Picklist | 是 | None / Limited / Unlimited |
| Carryover_Limit__c | Number(8,2) | 否 | 最多可结转额度 |
| Carryover_Expire_Month__c | Number(2,0) | 否 | 结转额度失效月份 |
| Carryover_Expire_Day__c | Number(2,0) | 否 | 结转额度失效日期 |
| Effective_From__c | Date | 否 | 生效开始日期 |
| Effective_To__c | Date | 否 | 生效结束日期 |
| Policy_Version__c | Number(6,0) | 是 | 当前规则版本号 |

设计说明：

- 休假类型不再由 `Leave_Request__c` 的静态 Picklist 完全承载，而是由可维护的类型目录驱动。
- 若需要尽量减少一次性改动，可在过渡期保留原 `Leave_Type__c` 作为快照文本，同时新增 `Leave_Type_Definition__c` Lookup 字段。
- 若希望后续完全配置驱动，建议最终将申请单、余额明细、报表都统一关联到 `Leave_Type_Definition__c`。
- 对于年假这类会随工龄递增的假种，推荐通过 `Accrual_Mode__c = Seniority` 驱动授予，而不是把“每年 +1 天”写死在 Apex 常量里。

### 工龄递增年假规则

对于需要“每年增加一天”的假种，推荐采用以下标准设计：

- 适用假种：通常是 `ANNUAL`
- 基础规则：`Base_Entitlement__c + 完整服务年限 × Accrual_Per_Year__c`
- 上限约束：最终结果不得超过 `Accrual_Max_Days__c`
- 资格门槛：若员工未满足 `Eligibility_Start_Months__c`，则本周期不授予或按制度折算
- 计算基准：
  - 若 `Service_Year_Basis__c = Calendar Year`，则每年重置时按当年基准日期计算工龄
  - 若 `Service_Year_Basis__c = Hire Anniversary`，则按员工入职周年触发额度变化

推荐默认制度：

- `Base_Entitlement__c = 5`
- `Accrual_Mode__c = Seniority`
- `Accrual_Per_Year__c = 1`
- `Accrual_Max_Days__c = 10`
- `Service_Year_Basis__c = Calendar Year`

设计说明：

- “每年 +1 天”本质上属于年度授予规则，不属于结转规则。
- 结转解决的是“上年未休完怎么处理”，工龄递增解决的是“本年应发多少额度”。
- 两者必须拆开设计，否则后续很难解释为什么某员工今年有 9 天、其中哪部分来自制度增长、哪部分来自上年结转。

---

## 15.4 余额模型增强

当前 `Leave_Balance__c` 仍可保留为“员工年度余额头对象”，但不再直接承载每一种假种的余额字段。

### `Leave_Balance__c`（升级后定位）

建议升级为年度汇总头对象：

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| User__c | Lookup(User) | 是 | 员工 |
| Balance_Year__c | Number(4,0) | 是 | 余额归属年度 |
| Status__c | Picklist | 是 | Open / Closed / Archived |
| Reset_Run_Key__c | Text(80) | 否 | 最近一次重置执行键 |
| Unique_Key__c | Text(50), Unique | 是 | `UserId-Year` |

说明：

- `Annual_Leave__c / Sick_Leave__c / Personal_Leave__c` 不再作为长期演进模型的核心字段。
- 这些字段可以在迁移期保留用于兼容，但新逻辑应逐步迁移到子表明细模型。

### 新增 `Leave_Balance_Line__c`

用于按“年度 + 假种”存储余额明细。

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| Leave_Balance__c | Master-Detail(Leave_Balance__c) | 是 | 所属年度余额头 |
| Leave_Type_Definition__c | Lookup(Leave_Type_Definition__c) | 是 | 假种 |
| Opening_Balance__c | Number(8,2) | 是 | 年初初始额度 |
| Granted__c | Number(8,2) | 是 | 本年度授予额度 |
| Carried_Forward__c | Number(8,2) | 是 | 上年结转额度 |
| Reserved__c | Number(8,2) | 是 | 已占用待核销额度 |
| Used__c | Number(8,2) | 是 | 已消耗额度 |
| Adjusted__c | Number(8,2) | 是 | 人工调整额度 |
| Expired__c | Number(8,2) | 是 | 已失效额度 |
| Granted_By_Policy__c | Number(8,2) | 是 | 按当前制度自动授予的额度 |
| Available__c | Formula(Number) | 是 | 可用余额 |
| Unique_Key__c | Text(120), Unique | 是 | `UserId-Year-TypeCode` |

`Available__c` 推荐公式：

`Opening_Balance__c + Granted__c + Granted_By_Policy__c + Carried_Forward__c + Adjusted__c - Reserved__c - Used__c - Expired__c`

### 新增 `Leave_Balance_Transaction__c`

用于记录余额流水，支持审计、回放、对账和幂等重试。

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| Leave_Balance_Line__c | Master-Detail(Leave_Balance_Line__c) | 是 | 所属余额明细 |
| Leave_Request__c | Lookup(Leave_Request__c) | 否 | 来源申请单 |
| Transaction_Type__c | Picklist | 是 | Grant / Reserve / Consume / Release / Carryover / Expire / Reset / Manual_Adjust |
| Quantity__c | Number(8,2) | 是 | 变动数量，正负均可 |
| Business_Date__c | Date | 是 | 业务生效日期 |
| Idempotency_Key__c | Text(120), Unique | 是 | 幂等键 |
| Comments__c | Long Text Area(1000) | 否 | 备注 |
| Policy_Version__c | Number(6,0) | 否 | 本次流水命中的制度版本 |

设计收益：

- 新增假种只需新增一条配置记录，不再新增余额字段。
- 每种余额变动都具备流水证据，可满足审计、导出、问题回放和防重复处理。
- 可以天然支持预占、释放、最终扣减，而不是只做一次性直接扣减。
- 可以区分“制度发放额度”和“结转额度”，从而支持工龄递增、特殊奖励和人工调整并存。

---

## 15.5 申请单模型增强

为保证历史口径稳定，`Leave_Request__c` 建议增加以下字段：

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| Leave_Type_Definition__c | Lookup(Leave_Type_Definition__c) | 是 | 关联假种配置 |
| Leave_Type_Code__c | Text(40) | 是 | 提交时快照的假种编码 |
| Leave_Type_Name__c | Text(80) | 是 | 提交时快照的假种名称 |
| Policy_Version__c | Number(6,0) | 是 | 提交时命中的规则版本 |
| Balance_Year__c | Number(4,0) | 是 | 本次申请主归属年度 |
| Entitlement_Snapshot__c | Number(8,2) | 否 | 提交时命中的制度年额度快照 |

说明：

- 历史单据必须保留快照，不应完全依赖运行时去读取最新假种配置。
- 如果假种配置后续停用、改名、修改审批要求，历史单据仍然可以被准确解释。
- `Balance_Year__c` 不应简单依赖 `System.today().year()`，而应基于业务日期和重置策略计算。
- 对于工龄递增制度，建议把提交时命中的年假制度额度快照到申请单或余额流水中，避免后续员工工龄变化后导致历史解释口径漂移。

---

## 15.6 年度重置与结转设计

建议新增年度重置服务与调度：

- `LeaveYearResetService`
- `LeaveYearResetBatch`
- `LeaveYearResetScheduler`

年度重置推荐流程：

1. 读取所有启用员工与启用假种配置。
2. 按假种的 `Reset_Mode__c` 判断是否需要生成下一年度余额。
3. 依据 `Accrual_Mode__c`、员工入职日期与工龄规则，计算新年度制度授予额度。
4. 计算上一周期剩余可结转额度，并应用 `Carryover_Limit__c`。
5. 为下一年度创建 `Leave_Balance__c` 头记录。
6. 为每个假种创建 `Leave_Balance_Line__c` 明细，并写入 `Opening / Grant / Carryover / Reset` 流水。
7. 对上一年度余额行写入 `Expire` 或 `Close` 处理结果。
8. 记录统一的执行批次键，保证重跑时按 `Idempotency_Key__c` 去重。

关键规则：

- “按年重置”不等于简单把余额清零，而是要区分“本年新授予额度”“结转额度”“过期额度”“未使用但不可结转额度”。
- 不同假种可以有不同重置策略，例如年假按自然年重置、病假不重置、婚假按事件一次性发放。
- 对于需要月度发放的假种，重置服务只负责初始化年度账户，周期授予由独立 `Grant` 任务处理。

### 工龄递增授予计算

若某假种采用 `Accrual_Mode__c = Seniority`，推荐使用如下计算模型：

`Granted_By_Policy = min(Base_Entitlement__c + Service_Years × Accrual_Per_Year__c, Accrual_Max_Days__c)`

其中：

- `Service_Years` 仅计算完整服务年限，不建议直接用自然年份差。
- 当 `Service_Year_Basis__c = Calendar Year` 时，建议以每年固定基准日计算，例如 `1 月 1 日`。
- 当 `Service_Year_Basis__c = Hire Anniversary` 时，建议以员工入职周年日作为工龄递增生效点。
- 若员工未满足 `Eligibility_Start_Months__c`，则本次授予为 `0` 或按制度折算，具体需在 HR 制度中明确。

推荐业务结论：

- 先采用“自然年统一发放 + 每满一年增加一天 + 设置上限”的模式，便于报表、审计和 HR 解释。
- 暂不推荐第一阶段就采用复杂的“满半年折算”或“周年日即时增发”，否则实现与对账复杂度显著上升。

### 年度可用额度组成

对于年假这类同时支持工龄递增和结转的假种，年度可用额度应拆解为：

- 本年制度授予额度：由工龄规则计算得出
- 上年结转额度：由结转规则计算得出
- 人工调整额度：由 HR 特批或补偿调整

推荐公式：

`Current_Year_Available = Granted_By_Policy__c + Carried_Forward__c + Adjusted__c - Used__c - Expired__c - Reserved__c`

这意味着：

- 工龄递增不会覆盖结转额度
- 结转额度不会改变员工本年制度等级
- 报表可以准确区分“制度发放”和“历史结转”

---

## 15.7 跨年与边界场景设计

增强方案必须覆盖以下边界场景：

- 跨年请假：例如 12 月 30 日到 1 月 3 日，必须按年度拆分扣减，不能全部扣减到当前年份。
- 补录审批：如果 2025 年的申请在 2026 年才最终审批，余额仍应命中 2025 年对应余额行，而不是 2026 年。
- 驳回或取消：若申请已预占余额，则必须释放 `Reserved__c`，不能只改状态。
- 重复调度：年度重置、授予、过期任务必须支持重跑不重复记账。
- 假种停用：停用后不允许新申请，但历史申请与历史余额仍可查询与报表统计。
- 规则改版：同一假种规则发生变化时，应通过 `Policy_Version__c` 或生效日期隔离历史与新单。
- 工龄变化：员工在新年度开始后工龄增长，不应反向改写上一年度已经生成的额度。
- 入职周年临界点：若采用 `Hire Anniversary`，必须明确周年日当天前后提交的申请命中哪一版额度。
- 入职未满门槛：若员工未达到 `Eligibility_Start_Months__c`，系统必须统一返回不可申请或额度为 0 的明确结果。
- 封顶后增长：当年假达到 `Accrual_Max_Days__c` 后，后续工龄增长不得继续增加制度额度。

---

## 15.8 跨年请假拆分扣减设计

对于跨越两个自然年度或两个余额周期的请假申请，系统不能把整单天数全部扣减到单一年度余额，而必须先拆分，再分别校验、预占和核销。

### 设计目标

- 跨年请假在余额层面必须可解释、可追溯、可对账。
- 申请单可以保持一个业务单据，但余额处理必须拆成多个年度分段。
- 校验失败时必须准确指出是哪个年度余额不足，而不是仅返回笼统的“余额不足”。

### 推荐模型

建议引入“申请单主记录 + 年度分段明细”的处理思路：

- 主记录：`Leave_Request__c`
- 分段记录：推荐新增 `Leave_Request_Segment__c`

### `Leave_Request_Segment__c`

用于记录同一申请在不同年度或不同余额周期中的拆分结果。

建议字段：

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| Leave_Request__c | Master-Detail(Leave_Request__c) | 是 | 所属请假申请 |
| Segment_Start_Date__c | Date | 是 | 分段开始日期 |
| Segment_End_Date__c | Date | 是 | 分段结束日期 |
| Balance_Year__c | Number(4,0) | 是 | 该段命中的余额年度 |
| Days__c | Number(8,2) | 是 | 该段请假天数 |
| Leave_Type_Definition__c | Lookup(Leave_Type_Definition__c) | 是 | 命中的假种 |
| Segment_Status__c | Picklist | 是 | Draft / Reserved / Consumed / Released |
| Unique_Key__c | Text(120), Unique | 是 | `RequestId-Year-Index` |

设计说明：

- 申请主单仍面向业务用户，避免让员工看到多条“拆开的请假单”。
- 余额、结转、年度扣减、审计和对账以 `Leave_Request_Segment__c` 为准。
- 后续若存在“工作日算法”“节假日排除”“小时级请假”，仍可以在 Segment 层扩展，而不必改主单语义。

### 拆分规则

当申请满足以下任一条件时，必须拆分：

- `Start_Date__c` 与 `End_Date__c` 跨越不同自然年
- 假种的 `Reset_Mode__c = Hire Anniversary` 且请假区间跨越周年边界
- 假种采用自定义余额周期且申请跨越周期切点

最小拆分原则：

- 优先按余额周期边界拆分，而不是机械按天拆分
- 只有跨越边界时才拆分，不跨边界则保持单段

示例：

- 申请区间：`2026-12-30` 到 `2027-01-03`
- 拆分结果：
  - Segment 1：`2026-12-30` 到 `2026-12-31`，命中 `2026` 年余额
  - Segment 2：`2027-01-01` 到 `2027-01-03`，命中 `2027` 年余额

### 校验与扣减顺序

推荐处理流程：

1. 根据请假区间和假种规则生成 Segment 草稿。
2. 逐段计算 `Days__c`。
3. 逐段解析 `Balance_Year__c`。
4. 逐段校验余额是否充足。
5. 全部通过后再逐段执行 `Reserve`。
6. 最终审批通过时，再逐段从 `Reserved` 转成 `Used`。

关键原则：

- 必须采用“全通过再提交”的事务思路，避免前半段已扣减、后半段失败导致余额脏数据。
- 若任一 Segment 校验失败，整个申请不得进入最终审批通过。
- 错误提示必须带出失败分段，例如“2026 年年假余额不足”。

### 跨年与结转的关系

对于支持结转的年假，跨年拆分后应分别应用各年度规则：

- `2026` 段只能消耗 `2026` 年可用余额
- `2027` 段只能消耗 `2027` 年的制度授予额度与结转额度
- 不允许把 `2027` 年的额度提前借给 `2026` 年的分段使用

这意味着：

- 即便整张申请连续，余额口径仍然以 Segment 所属年度为准
- 年度结转只影响进入新年度后的 Segment，不影响上一年度 Segment

### 审计与报表

跨年拆分后建议支持以下报表口径：

- 按申请主单统计审批数量
- 按 Segment 统计年度用假天数
- 按 Segment 统计不同年度的余额消耗
- 按 Segment 统计结转额度实际使用情况

---

## 15.9 审批策略配置化设计

当前审批设计已支持经理审批和可选 HR 审批，下一步应将审批路径从固定流程提升为“假种策略 + 金额/天数阈值 + 组织角色”的配置组合。

### 设计目标

- 不同假种可走不同审批路径。
- 审批链路必须可配置，而非散落在代码和 Approval Process 中硬编码。
- 审批策略变化不能破坏历史单据解释。

### 配置模型

建议在 `Leave_Type_Definition__c` 上继续增加审批相关字段：

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| Approval_Mode__c | Picklist | 是 | Manager Only / Manager Then HR / HR Only / Configurable |
| Auto_Approve_Below_Days__c | Number(8,2) | 否 | 小于等于该阈值时可自动通过 |
| Escalate_Above_Days__c | Number(8,2) | 否 | 超过该阈值时需升级审批 |
| Escalation_Target__c | Picklist | 否 | HR / Manager Manager / Custom Queue |
| Approval_Group_Key__c | Text(80) | 否 | 审批组或队列配置键 |

设计说明：

- `Requires_HR_Approval__c` 可作为基础兼容字段保留。
- 中长期应以 `Approval_Mode__c` 为主，表达完整审批语义。
- `Approval_Group_Key__c` 用于对接 Queue、Public Group 或自定义元数据，不允许硬编码具体用户。

### 推荐审批策略

建议支持以下基线模式：

- `Manager Only`
  - 普通年假、事假等默认场景
- `Manager Then HR`
  - 病假超过一定天数、婚假、产假等需要 HR 留痕的场景
- `HR Only`
  - 纯制度性校验、无需经理审批的特殊场景
- `Configurable`
  - 后续接入阈值升级、多级审批或特殊组织策略时使用

### 审批路由规则

推荐路由优先级：

1. 先读取 `Leave_Type_Definition__c` 中的审批策略。
2. 再结合申请天数、员工组织层级、是否跨年、是否触发特殊阈值判断是否升级审批。
3. 最终解析出每一步审批节点与审批人来源。

推荐审批人来源：

- 直属经理：来源于 `Leave_Request__c.Manager__c`
- HR：来源于 `Approval_Group_Key__c` 对应的 Group / Queue
- 上级经理：来源于经理的上级层级解析

禁止项：

- 禁止把审批用户硬编码到 Apex
- 禁止把审批人解析逻辑散落在多个 Flow 中互相覆盖
- 禁止审批策略只存于页面说明或人工约定

### 典型场景

示例 1：普通年假

- 审批模式：`Manager Only`
- 处理结果：经理审批通过后直接进入最终核销

示例 2：病假超过 3 天

- 审批模式：`Manager Then HR`
- 阈值：`Escalate_Above_Days__c = 3`
- 处理结果：经理通过后进入 HR 审批

示例 3：婚假

- 审批模式：`HR Only`
- 处理结果：由 HR 或指定审批组直接审批

### 审批与余额的衔接

审批策略必须和余额处理解耦但保持顺序一致：

- 提交时：生成 Segment 并做余额可用性校验
- 中间审批中：仅保留 `Reserved` 状态，不做最终消耗
- 最终审批通过：逐段把 `Reserved` 转成 `Used`
- 任一步驳回：逐段释放 `Reserved`

关键原则：

- 审批路径变化不应改变余额核销规则
- 余额核销时点必须统一以“最终审批通过”为准
- 审批历史与余额流水必须可关联回同一申请和同一 Segment

### 历史快照

为避免审批策略调整后影响历史解释，建议在申请单或审批流水中额外快照：

- `Approval_Mode_Snapshot__c`
- `Approval_Target_Snapshot__c`
- `Approval_Policy_Version__c`

这样即使未来某假种从“经理审批”改成“经理 + HR 审批”，历史单据仍能按当时制度解释。

---

## 15.10 服务层增强建议

当前 `LeaveService` 建议从固定字段分支改造成策略驱动服务。

推荐服务职责：

- `resolveLeaveTypePolicy()`
- `resolveBalanceYear()`
- `reserveBalance()`
- `releaseReservedBalance()`
- `consumeReservedBalance()`
- `grantEntitlement()`
- `calculateEntitlementBySeniority()`
- `carryForwardBalance()`
- `expireCarryover()`
- `resetAnnualBalance()`

实现原则：

- 余额校验不再写成 `if (leaveType == 'Annual') ...` 这样的固定分支，而是先解析假种配置，再定位对应余额行。
- 最终审批通过时，应优先把已预占额度转成 `Used__c`，而不是再次重新计算扣减。
- 经理审批、HR 审批、阈值升级审批等路由条件应尽量来自假种配置和策略判断，而不是散落在多个 Flow / Trigger 中。
- 工龄递增计算必须独立封装，禁止在多个 Trigger / Flow / Batch 中重复各写一套公式。

---

## 15.11 推荐演进路径

为了控制上线风险，建议分阶段升级：

### 第一阶段：兼容扩展

- 保留现有 `Leave_Balance__c` 和现有审批主流程。
- 新增 `Leave_Type_Definition__c`、`Leave_Balance_Line__c`、`Leave_Balance_Transaction__c`。
- 在新服务层中双写旧字段与新明细，建立迁移验证能力。
- 工龄递增规则先进入设计与配置层，不强制在第一阶段全部上线。
- 跨年拆分和审批策略配置化先完成设计，不要求第一阶段一次性全部切换。

### 第二阶段：切换主模型

- LWC、Flow、Apex 改为优先读取新假种目录与新余额明细。
- `Leave_Type__c` 静态 Picklist 逐步退化为快照或展示字段。
- 年度重置、结转、过期全部切到新流水模型。
- 将“每年 +1 天”这类工龄递增规则切入年度授予服务，而不是继续依赖人工维护年假余额。
- 将跨年 Segment、审批模式解析、阈值升级审批切入统一服务层。

### 第三阶段：收敛遗留

- 在确认报表、审批、导出、审计都稳定后，逐步弱化 `Annual_Leave__c / Sick_Leave__c / Personal_Leave__c` 的业务职责。
- 最终把固定字段模型降级为兼容历史或彻底移除。

---

## 16. 总结

当前版本设计已经和仓库中的 Salesforce 开发规范保持一致：

- 数据模型已实现请假类型与余额模型的闭环一致
- 审批路由采用单一可信来源
- 员工、经理、HR 的安全边界清晰
- 审计能力已经纳入基线数据模型
- Flow 与 Apex 的职责边界清晰
- Lightning App 承载方式明确，可支持分角色导航与页面分配
- 在引入可配置假种目录、余额明细流水、年度重置服务后，系统可以进一步支撑假种扩展、年度结转与长期演进
