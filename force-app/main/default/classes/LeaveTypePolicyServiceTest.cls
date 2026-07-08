@IsTest
private class LeaveTypePolicyServiceTest {

    @IsTest
    static void testGetPolicyByLeaveTypeValueUsesDefinition() {
        insert new Leave_Type_Definition__c(
            Name = 'Annual Leave Policy',
            Type_Code__c = 'ANNUAL',
            Is_Active__c = true,
            Allow_Carryover__c = true,
            Carryover_Limit__c = 7,
            Carryover_Expire_Month__c = 4,
            Carryover_Expire_Day__c = 15,
            Requires_HR_Approval__c = true,
            Policy_Version__c = 3
        );

        LeaveTypePolicyService.LeaveTypePolicy policy =
            LeaveTypePolicyService.getPolicyByLeaveTypeValue('Annual');

        Assert.areEqual(true, policy.isDefined, 'Should resolve configured policy.');
        Assert.areEqual('ANNUAL', policy.typeCode);
        Assert.areEqual('Annual Leave Policy', policy.typeName);
        Assert.areEqual(7, policy.carryoverLimit);
        Assert.areEqual(4, policy.carryoverExpireMonth);
        Assert.areEqual(15, policy.carryoverExpireDay);
        Assert.areEqual(true, policy.requiresHrApproval);
        Assert.areEqual(3, Integer.valueOf(String.valueOf(policy.policyVersion)));
    }

    @IsTest
    static void testCarryForwardAnnualLeaveUsesConfiguredPolicy() {
        Integer sourceYear = 2026;
        Integer targetYear = 2027;

        insert new Leave_Type_Definition__c(
            Name = 'Annual Leave Policy',
            Type_Code__c = 'ANNUAL',
            Is_Active__c = true,
            Allow_Carryover__c = true,
            Carryover_Limit__c = 2,
            Carryover_Expire_Month__c = 2,
            Carryover_Expire_Day__c = 28,
            Policy_Version__c = 2
        );
        insert new Leave_Balance__c(
            User__c = UserInfo.getUserId(),
            Year__c = sourceYear,
            Annual_Leave__c = 9,
            Sick_Leave__c = 0,
            Personal_Leave__c = 0
        );

        Test.startTest();
        LeaveAnnualCarryoverService.carryForwardAnnualLeave(sourceYear, targetYear);
        Test.stopTest();

        Leave_Balance__c balance = [
            SELECT Carryover_Annual_Leave__c, Carryover_Expiry_Date__c
            FROM Leave_Balance__c
            WHERE User__c = :UserInfo.getUserId()
            AND Year__c = :targetYear
            LIMIT 1
        ];

        Assert.areEqual(2, balance.Carryover_Annual_Leave__c, 'Should use configured carryover limit.');
        Assert.areEqual(Date.newInstance(targetYear, 2, 28), balance.Carryover_Expiry_Date__c);
    }

    @IsTest
    static void testRequestSnapshotsConfiguredLeaveTypeAndInactivePolicyBlocksSubmit() {
        Integer yearValue = Date.today().year();

        insert new Leave_Type_Definition__c(
            Name = 'Personal Leave Policy',
            Type_Code__c = 'PERSONAL',
            Is_Active__c = false,
            Allow_Carryover__c = false,
            Policy_Version__c = 5
        );
        insert new Leave_Balance__c(
            User__c = UserInfo.getUserId(),
            Year__c = yearValue,
            Annual_Leave__c = 10,
            Sick_Leave__c = 10,
            Personal_Leave__c = 10
        );

        Leave_Request__c requestRecord = new Leave_Request__c(
            Employee__c = UserInfo.getUserId(),
            Leave_Type__c = 'Personal',
            Start_Date__c = Date.today().addDays(5),
            End_Date__c = Date.today().addDays(6),
            Status__c = 'Draft',
            Balance_Deducted__c = false
        );
        insert requestRecord;

        Leave_Request__c insertedRequest = [
            SELECT Leave_Type__c, Start_Date__c, End_Date__c, Employee__c, Status__c,
                   Leave_Type_Definition__c, Leave_Type_Code__c, Leave_Type_Name__c, Policy_Version__c
            FROM Leave_Request__c
            WHERE Id = :requestRecord.Id
        ];

        Assert.areEqual('PERSONAL', insertedRequest.Leave_Type_Code__c);
        Assert.areEqual('Personal Leave Policy', insertedRequest.Leave_Type_Name__c);
        Assert.areEqual(5, Integer.valueOf(String.valueOf(insertedRequest.Policy_Version__c)));
        Assert.isNotNull(insertedRequest.Leave_Type_Definition__c, 'Should snapshot configured definition.');

        insertedRequest.Status__c = 'Submitted';
        Database.SaveResult saveResult = Database.update(insertedRequest, false);

        Assert.areEqual(false, saveResult.isSuccess(), 'Inactive configured leave type should block submission.');
        Assert.isTrue(
            saveResult.getErrors()[0].getMessage().contains('inactive'),
            'Should show inactive policy validation message.'
        );
    }
}
