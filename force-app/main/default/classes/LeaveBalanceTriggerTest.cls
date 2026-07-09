@IsTest
private class LeaveBalanceTriggerTest {

    @IsTest
    static void testInsertBalanceHeadInitializesLedgerLinesFromManualCreate() {
        createLeaveTypeDefinition('ANNUAL', true);
        createLeaveTypeDefinition('SICK', false);
        createLeaveTypeDefinition('PERSONAL', false);

        Leave_Balance__c balanceHead = new Leave_Balance__c(
            User__c = UserInfo.getUserId(),
            Balance_Year__c = 2026,
            Annual_Leave__c = 12,
            Carryover_Annual_Leave__c = 3,
            Sick_Leave__c = 5,
            Personal_Leave__c = 2
        );

        Test.startTest();
        insert balanceHead;
        Test.stopTest();

        Leave_Balance__c persistedHead = [
            SELECT User__c, Year__c, Balance_Year__c, Status__c, Unique_Key__c
            FROM Leave_Balance__c
            WHERE Id = :balanceHead.Id
        ];
        Assert.areEqual(2026, Integer.valueOf(String.valueOf(persistedHead.Year__c)));
        Assert.areEqual(2026, Integer.valueOf(String.valueOf(persistedHead.Balance_Year__c)));
        Assert.areEqual('Open', persistedHead.Status__c);
        Assert.areEqual(
            UserInfo.getUserId() + '-2026',
            persistedHead.Unique_Key__c
        );

        Map<String, Leave_Balance_Line__c> lineByTypeCode = new Map<String, Leave_Balance_Line__c>();
        for (Leave_Balance_Line__c lineRecord : [
            SELECT Granted_By_Policy__c, Carried_Forward__c, Available__c,
                   Leave_Type_Definition__r.Type_Code__c
            FROM Leave_Balance_Line__c
            WHERE Leave_Balance__c = :balanceHead.Id
        ]) {
            lineByTypeCode.put(lineRecord.Leave_Type_Definition__r.Type_Code__c, lineRecord);
        }

        Assert.areEqual(3, lineByTypeCode.size());
        Assert.areEqual(12, lineByTypeCode.get('ANNUAL').Granted_By_Policy__c);
        Assert.areEqual(3, lineByTypeCode.get('ANNUAL').Carried_Forward__c);
        Assert.areEqual(15, lineByTypeCode.get('ANNUAL').Available__c);
        Assert.areEqual(5, lineByTypeCode.get('SICK').Granted_By_Policy__c);
        Assert.areEqual(5, lineByTypeCode.get('SICK').Available__c);
        Assert.areEqual(2, lineByTypeCode.get('PERSONAL').Granted_By_Policy__c);
        Assert.areEqual(2, lineByTypeCode.get('PERSONAL').Available__c);
    }

    private static void createLeaveTypeDefinition(String typeCode, Boolean allowCarryover) {
        insert new Leave_Type_Definition__c(
            Name = typeCode + ' Policy',
            Type_Code__c = typeCode,
            Is_Active__c = true,
            Allow_Carryover__c = allowCarryover,
            Policy_Version__c = 1
        );
    }
}
