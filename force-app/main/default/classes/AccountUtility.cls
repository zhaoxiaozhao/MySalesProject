/*
作者: OpenAI
创建时间: 2026-07-15
功能: 查询 Account 年收入并输出到调试日志
修改人: OpenAI
修改时间: 2026-07-15
修改内容: 新增 viewAnnualRevenue 方法
*/
public class AccountUtility
{
    /*
描述: 查询所有 Account 的名称和年收入, 并逐条输出到调试日志
返回值: 无
*/
    public static void viewAnnualRevenue()
    {
        List<Account> accountsList = [
            SELECT Name, AnnualRevenue
            FROM Account
        ];

        for (Account accountRecord : accountsList)
        {
            String acctRev = accountRecord.Name + ' : ' + accountRecord.AnnualRevenue;
            System.debug(acctRev);
        }
    }
}
