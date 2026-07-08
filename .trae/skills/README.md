# Salesforce Skills Bundle

这组 skills 基于 `docs/Salesforce开发规范.pdf` 生成，适用于在 opencode 中约束 Salesforce 开发行为。

## Skills

- `salesforce-development-standard`
  - 总入口。适用于一般性的 Salesforce 开发、修改、重构请求。
- `salesforce-naming-standard`
  - 处理对象、字段、Class、Trigger、VF、Batch、Schedule、测试类命名。
- `salesforce-object-field-design`
  - 处理对象建模、字段设计、关系类型、校验规则、Record Type、页面布局和字段集。
- `salesforce-apex-style`
  - 处理 Apex/Trigger/控制器的格式、注释、行长、嵌套和模块化。
- `salesforce-bulkification-and-limits`
  - 处理 Governor Limits、批量化、SOQL/DML 位置和硬编码风险。
- `salesforce-test-standard`
  - 处理测试类命名、结构、断言和覆盖要求。
- `salesforce-visualforce-fieldset`
  - 处理 Visualforce 页面、控制器和 Field Set 配置化展示。
- `salesforce-review-standard`
  - 处理按规范执行的代码审查和合并前自检。

## 规范来源摘要

PDF 中的核心规则主要包括：

- 命名规范：禁止拼音，按组件类型统一命名
- 代码规范：统一大括号、缩进、浅嵌套、注释
- Apex 最佳实践：禁止循环内 SOQL/DML，只查必要字段
- 测试规范：准备数据、执行、验证三段式
- 可配置化：VF 优先考虑 Field Set
- 可维护性：避免硬编码 ID、名称、角色名，优先配置化
