---
name: "salesforce-naming-standard"
description: "约束 Salesforce 元数据与代码命名。创建或重命名对象、字段、Class、Trigger、VF、Batch、Schedule、测试类时调用。"
---

# Salesforce 命名规范

用于统一 Salesforce 元数据和代码资产的命名方式。

## 核心规则

- 禁止使用拼音。
- 禁止使用无意义缩写。
- 名称必须直接表达业务语义。

## 命名规则

### 对象 API

- 规则：按英文语义拆词，单词首字母大写，单词之间用 `_` 连接。
- 自定义对象后缀由平台补充为 `__c`。
- 示例：`Weibo_Account__c`

如果对象标签是中文，先翻译成英文，再按规则命名。

### 字段 API

- 规则：描述字段含义的英文单词首字母大写，用 `_` 连接。
- 示例：`Weibo_Account_ID__c`

对于 Lookup 字段：

- 字段名优先使用被引用对象名。
- 子关系名使用当前对象名称表达。

### Class

- 规则：PascalCase。
- 示例：`OrderItem`

### Trigger

- 规则：`对象名 + 功能描述`
- 示例：`AccountAutoSetName`

### Visualforce 页面

- 规则：按页面功能命名，PascalCase。
- 示例：`OrderTracking`

### VF 控制器

- 规则：`页面名 + Controller`
- 示例：`OrderTrackingController`

### Web Service Class

- 规则：`功能描述 + WS`
- 示例：`CalculationPriceWS`

### Batch Class

- 规则：`功能描述 + Batch`
- 示例：`AutoUpdateAccountStatusBatch`

### Schedule Class

- 规则：`功能描述 + Schedule` 或团队既有缩写风格。
- 示例：`AutoUpdateAccountStatusSchedule`

### 测试类

- 规则：以 `Test_` 开头，后接被测类名。
- 示例：`Test_AutoUpdateAccountStatusBatch`

### 常量

- 全大写。
- 单词之间用 `_`。
- 尽量控制在 16 个字符以内。
- 示例：`PAGE_SIZE`

### 变量

- lowerCamelCase。
- 不以下划线或美元符开头。
- 名称简短且有意义，避免单字符变量名。
- 示例：`userName`

### 方法

- 使用动词或动宾结构。
- lowerCamelCase。
- 示例：`checkStatus`

## 输出要求

当你生成任何 Salesforce 资产时：

1. 先给出最终命名。
2. 简要说明命名依据。
3. 如果原始需求使用中文标签，补充对应英文翻译。
