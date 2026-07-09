@IsTest
private class LeaveAnnualCarryoverServiceTest {

    @IsTest
    static void testCarryForwardAnnualLeaveCreatesTargetBalance() {
        Integer sourceYear = 2026;
        Integer targetYear = 2027;

        insert new Leave_Balance__c(
            User__c = UserInfo.getUserId(),
            Year__c = sourceYear,
            Annual_Leave__c = 8,
            Sick_Leave__c = 2,
            Personal_Leave__c = 1
        );

        Test.startTest();
        LeaveAnnualCarryoverService.carryForwardAnnualLeave(sourceYear, targetYear, 5, 3, 31);
        LeaveAnnualCarryoverService.carryForwardAnnualLeave(sourceYear, targetYear, 5, 3, 31);
        Test.stopTest();

        List<Leave_Balance__c> balances = [
            SELECT Year__c, Carryover_Annual_Leave__c, Carryover_Expiry_Date__c,
                   Carryover_Source_Year__c, Carryover_Run_Key__c
            FROM Leave_Balance__c
            WHERE User__c = :UserInfo.getUserId()
            AND Year__c = :targetYear
        ];

        Assert.areEqual(1, balances.size(), 'Should only create one target balance record.');
        Assert.areEqual(5, balances[0].Carryover_Annual_Leave__c, 'Should cap carryover at configured limit.');
        Assert.areEqual(Date.newInstance(targetYear, 3, 31), balances[0].Carryover_Expiry_Date__c);
        Assert.areEqual(sourceYear, Integer.valueOf(String.valueOf(balances[0].Carryover_Source_Year__c)));
        Assert.areEqual('ANNUAL-2026-2027', balances[0].Carryover_Run_Key__c);
    }

    @IsTest
    static void testExpireCarryoverClearsExpiredAmount() {
        Integer yearValue = Date.today().year();

        insert new Leave_Balance__c(
            User__c = UserInfo.getUserId(),
            Year__c = yearValue,
            Annual_Leave__c = 10,
            Sick_Leave__c = 0,
            Personal_Leave__c = 0,
            Carryover_Annual_Leave__c = 3,
            Carryover_Expiry_Date__c = Date.today().addDays(-1)
        );

        Test.startTest();
        Integer expiredCount = LeaveAnnualCarryoverService.expireCarryover(Date.today());
        Test.stopTest();

        Leave_Balance__c balance = [
            SELECT Carryover_Annual_Leave__c
            FROM Leave_Balance__c
            WHERE User__c = :UserInfo.getUserId()
            AND Year__c = :yearValue
            LIMIT 1
        ];

        Assert.areEqual(1, expiredCount, 'Should expire one carryover balance.');
        Assert.areEqual(0, balance.Carryover_Annual_Leave__c, 'Expired carryover should be cleared.');
    }

    @IsTest
    static void testDeductBalanceConsumesCarryoverFirst() {
        Integer yearValue = Date.today().year();

        Leave_Type_Definition__c annualDefinition = new Leave_Type_Definition__c(
            Name = 'Annual Leave Policy',
            Type_Code__c = 'ANNUAL',
            Is_Active__c = true,
            Allow_Carryover__c = true,
            Policy_Version__c = 1
        );
        insert annualDefinition;

        insert new Leave_Balance__c(
            User__c = UserInfo.getUserId(),
            Year__c = yearValue,
            Annual_Leave__c = 10,
            Sick_Leave__c = 0,
            Personal_Leave__c = 0,
            Carryover_Annual_Leave__c = 3,
            Carryover_Expiry_Date__c = Date.today().addDays(30)
        );

        Leave_Request__c requestRecord = new Leave_Request__c(
            Employee__c = UserInfo.getUserId(),
            Leave_Type_Definition__c = annualDefinition.Id,
            Start_Date__c = Date.today(),
            End_Date__c = Date.today().addDays(4),
            Days__c = 5,
            Balance_Year__c = yearValue,
            Status__c = 'Approved',
            Balance_Deducted__c = false
        );
        insert requestRecord;

        Test.startTest();
        LeaveService.deductBalance(requestRecord.Id);
        Test.stopTest();

        Leave_Balance__c balance = [
            SELECT Annual_Leave__c, Carryover_Annual_Leave__c
            FROM Leave_Balance__c
            WHERE User__c = :UserInfo.getUserId()
            AND Year__c = :yearValue
            LIMIT 1
        ];
        Leave_Request__c updatedRequest = [
            SELECT Balance_Deducted__c
            FROM Leave_Request__c
            WHERE Id = :requestRecord.Id
        ];

        Assert.areEqual(8, balance.Annual_Leave__c, 'Should consume regular annual leave after carryover is used.');
        Assert.areEqual(0, balance.Carryover_Annual_Leave__c, 'Should consume carryover leave first.');
        Assert.areEqual(true, updatedRequest.Balance_Deducted__c, 'Request should be marked as deducted.');
    }
}
