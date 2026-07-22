/*
作者: OpenAI
创建时间: 2026-07-16
功能: 为 NewCaseList Visualforce 页面提供新建 Case 列表
修改人: OpenAI
修改时间: 2026-07-16
修改内容: 新增 getNewCases 方法
*/
public class NewCaseListController
{
    /*
描述: 查询所有状态为 New 的 Case 记录
返回值: 新建状态的 Case 列表
*/
    public List<Case> getNewCases()
    {
        return [
            SELECT Id, CaseNumber
            FROM Case
            WHERE Status = 'New'
        ];
    }
}
