/*
作者: OpenAI
创建时间: 2026-07-15
功能: 按练习题要求批量创建 Account 示例数据
修改人: OpenAI
修改时间: 2026-07-15
修改内容: 对齐练习题, 仅保留 insertAccount 方法
*/
public class AccountHandler
{
    /*
描述: 使用 while 循环构造多条 Account 记录, 并通过一次 DML 统一插入
参数 numberOfAccounts: 需要创建的 Account 数量
返回值: 无
*/
    public static void insertAccount(Integer numberOfAccounts)
    {
        if (numberOfAccounts == null || numberOfAccounts <= 0)
        {
            return;
        }

        List<Account> addAccounts = new List<Account>();
        Integer n = 1;

        while (n <= numberOfAccounts)
        {
            addAccounts.add(new Account(
                Name = 'Acme Inc ' + n,
                AccountNumber = 'A000' + n
            ));
            n++;
        }

        insert addAccounts;
    }
}
