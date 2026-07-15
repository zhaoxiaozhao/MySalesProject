/*
作者: OpenAI
创建时间: 2026-07-15
功能: 查询最近 30 天挂牌的房产并输出经纪人邮箱
修改人: OpenAI
修改时间: 2026-07-15
修改内容: 新增 newListedProperties 方法
*/
public class PropertyUtility
{
    /*
描述: 查询最近 30 天挂牌的 Property 记录, 并逐条输出房产名称和经纪人邮箱
返回值: 无
*/
    public static void newListedProperties()
    {
        List<Property__c> newPropList = [
            SELECT Name, Broker__r.Email__c, Days_On_Market__c
            FROM Property__c
            WHERE Days_On_Market__c <= 30
        ];

        for (Property__c propertyRecord : newPropList)
        {
            String propEmail = propertyRecord.Name + ' : ' + propertyRecord.Broker__r.Email__c;
            System.debug(propEmail);
        }
    }
}
