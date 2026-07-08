---
name: "salesforce-bulkification-and-limits"
description: "约束批量化、查询与硬编码风险。实现触发器、批处理、批量更新、SOQL/SOSL 或高数据量逻辑时调用。"
---

# Salesforce 批量化与治理限制

用于避免 Governor Limits 违规，并提升 Apex 在批量场景下的稳定性。

## 强制规则

### 禁止循环内 SOQL / DML

- 禁止在 `for` 循环中执行 SOQL。
- 禁止在 `for` 循环中执行 `insert/update/upsert/delete`。
- 必须先收集数据，再统一查询、统一提交。

## 查询原则

- 只查询当前逻辑真正需要的字段。
- 不要为了“以后可能用到”而把字段全查出来。
- 关系查询、聚合查询、SOSL 也要保持最小读取原则。

例如如果只更新 `Account.Name`，那查询里只取 `Name` 即可，不额外带出其他字段。

## 批量化实现方式

- 先使用 `Set<Id>`、`Map<Id, SObject>`、`List<SObject>` 收集上下文。
- 再一次性查询关联数据。
- 最后统一做 DML。

推荐骨架：

```apex
Set<Id> accountIds = new Set<Id>();
for (Contact c : Trigger.new)
{
    if (c.AccountId != null)
    {
        accountIds.add(c.AccountId);
    }
}

Map<Id, Account> accountMap = new Map<Id, Account>(
    [SELECT Name FROM Account WHERE Id IN :accountIds]
);

for (Contact c : Trigger.new)
{
    if (!accountMap.containsKey(c.AccountId))
    {
        continue;
    }

    accountMap.get(c.AccountId).Name = c.LastName;
}

update accountMap.values();
```

## 硬编码限制

代码中禁止硬编码以下内容：

- 记录 ID
- `RecordTypeId`
- 用户 ID
- 记录名称
- 用户名称
- 角色名称

如果确有必要引用可变值：

- 优先使用 `Custom Setting` 或其他配置化机制承载。

补充禁止项：

- 记录名称
- 简档名称
- 角色名称

## 设计建议

- 大块逻辑按职责拆分，避免一个方法中堆叠所有处理。
- 共享逻辑提取为公共方法，降低重复。
- 面向批量输入设计，不按单条数据思维写 Trigger。

## 生成代码时的默认检查

1. 是否出现循环内 SOQL。
2. 是否出现循环内 DML。
3. 是否查询了无用字段。
4. 是否存在 ID、用户名、角色名等硬编码。
5. 是否能改为集合化和映射化处理。

## 输出要求

当你返回实现方案时，应显式说明：

- 数据收集阶段
- 统一查询阶段
- 统一更新阶段
- 用于规避 Governor Limits 的关键设计点
