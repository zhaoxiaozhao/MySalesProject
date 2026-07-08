---
name: "salesforce-visualforce-fieldset"
description: "约束 Visualforce 页面、控制器和 Field Set 用法。实现 VF 页面、页面控制器或可配置展示界面时调用。"
---

# Salesforce Visualforce 与 Field Set 规范

用于降低 Visualforce 页面的耦合度和后续维护成本。

## 命名

- Visualforce 页面：按功能命名，使用 PascalCase。
- 页面控制器：`页面名 + Controller`

示例：

- 页面：`OrderTracking`
- 控制器：`OrderTrackingController`

## 页面实现原则

- 页面展示字段较多且存在变更可能时，优先考虑 `Field Set`。
- 尽量避免把展示列和字段顺序硬编码在 VF 标签与 Apex 中。

## Field Set 使用原则

- 当页面字段经常调整时，通过对象上的 `Field Set` 驱动展示。
- 调整展示列时，应优先改配置，不改代码。
- 页面显示内容应尽量与对象字段集绑定。
- 常见做法是用 `DisplayColumns` 字段集承载页面展示列，用 `Filter` 字段集承载筛选条件。
- 可通过对象配置界面把字段直接拖入字段集中，而不是修改 VF 页面代码。
- 调整后保存并刷新页面即可生效。
- 单个 `Field Set` 最多 50 个字段。

## 适用场景

- 明细页附属信息展示
- 可配置字段列表
- 需要频繁变更展示字段的页面
- 类似“客户联系人”这类列很多、展示经常变化的列表页

## 设计收益

- 减少 VF 页面反复改版时的代码改动
- 降低 Apex 控制器随展示调整而联动修改的次数
- 把展示差异转为配置差异

## 输出要求

当你实现 VF 页面时：

1. 说明是否适合使用 `Field Set`。
2. 如果适合，优先给出基于 `Field Set` 的方案。
3. 明确页面名和控制器名是否符合规范。
4. 如果是列表或筛选页面，优先给出展示字段集和筛选字段集的命名方案。
