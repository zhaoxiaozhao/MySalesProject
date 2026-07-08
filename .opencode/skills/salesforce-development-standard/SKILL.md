---
name: "salesforce-development-standard"
description: "统一约束 Salesforce 开发实现。用户要求编写、修改、重构 Apex、Trigger、Visualforce、Batch、Schedule 或对象字段设计时调用。"
---

# Salesforce 开发总规范

基于 `docs/Salesforce开发规范.pdf` 提炼的总规范。用于在实现 Salesforce 功能时先建立统一边界，再进入具体编码。

## 适用范围

- Apex Class
- Trigger
- Visualforce 页面与控制器
- Web Service Class
- Batch / Schedule
- 自定义对象与字段
- 测试类

## 使用方式

收到 Salesforce 开发请求后，先按下面顺序判断：

1. 先确认本次产物类型：对象/字段、Apex、Trigger、VF、Batch、Schedule、测试。
2. 先套用命名规范，再套用代码规范。
3. 涉及批量数据处理、查询、更新时，严格按 Governor Limits 约束设计。
4. 涉及页面展示时，优先考虑 Field Set 和可配置化。
5. 完成实现后，按测试与审查清单自检。

## 总体原则

- 禁止出现拼音命名和无实际含义的命名。
- 命名应直接表达业务语义和组件职责。
- 统一代码风格、缩进、注释格式和方法边界。
- 尽量浅嵌套，避免深层 `if/for` 叠加。
- 禁止在 `for` 循环中执行 SOQL 和 DML。
- 查询只取需要的字段，避免过量字段读取。
- 禁止硬编码记录 ID、RecordTypeId、用户 ID、名称、角色名等。
- 优先通过配置解决变化点，例如 Custom Setting。
- 测试必须包含准备数据、执行、验证三个阶段。

## Developer Edition Org 注意事项

在 **Developer Edition（非 Scratch Org）** 中部署自定义对象和字段时，必须注意以下问题：

### FLS（字段级安全）不会自动授权

- Scratch Org：System Admin Profile 自动拥有所有自定义字段的 FLS。
- Developer Edition：必须通过 **Permission Set** 显式授权，否则 REST API 和 `sf data query` 会报 `No such column` 错误。

### Permission Set FLS 的限制

- `required=true` 的字段 **不能** 在 Permission Set 的 `fieldPermissions` 中设置 FLS，metadata 部署会报错 `You cannot deploy to a required field`。
- 解决方法：将非必填字段（`required=false`）的 FLS 放在 Permission Set 中；必填字段要么改为 `required=false` + Validation Rule 兜底，要么通过 Profile 而非 Permission Set 授权。

### 部署流程参考

```
创建对象 + 字段（required=false 优先）
  → 创建 Permission Set + 分配用户
  → 验证 sf data query 可查询所有字段
  → 用 Validation Rule 替代 required=true 的业务校验
```

## 交付前检查

- 命名是否符合对象、字段、类、Trigger、VF、Batch、Schedule、测试类规则。
- 代码块是否统一换行、统一大括号风格。
- 方法前是否有用途、参数、返回值、异常说明。
- 是否存在深嵌套，可否用提前返回或 `continue` 降层。
- 是否存在循环内 SOQL/DML。
- 是否存在硬编码 ID、名称、用户名、角色名。
- 是否已经补齐测试和关键断言。
- VF 页面是否可以通过 Field Set 降低后续变更成本。
