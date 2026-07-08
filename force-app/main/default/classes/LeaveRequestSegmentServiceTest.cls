@IsTest
private class LeaveRequestSegmentServiceTest {

    @IsTest
    static void testBuildSegmentsSplitsCrossYearRequest() {
        List<LeaveRequestSegmentService.SegmentDetail> segments =
            LeaveRequestSegmentService.buildSegments(
                Date.newInstance(2026, 12, 30),
                Date.newInstance(2027, 1, 3),
                null
            );

        Assert.areEqual(2, segments.size(), 'Cross-year request should be split into two segments.');
        Assert.areEqual(Date.newInstance(2026, 12, 30), segments[0].segmentStartDate);
        Assert.areEqual(Date.newInstance(2026, 12, 31), segments[0].segmentEndDate);
        Assert.areEqual(2026, segments[0].balanceYear);
        Assert.areEqual(2, segments[0].days);
        Assert.areEqual(Date.newInstance(2027, 1, 1), segments[1].segmentStartDate);
        Assert.areEqual(Date.newInstance(2027, 1, 3), segments[1].segmentEndDate);
        Assert.areEqual(2027, segments[1].balanceYear);
        Assert.areEqual(3, segments[1].days);
    }

    @IsTest
    static void testCrossYearValidationAndSegmentCreation() {
        User employee = createEmployeeUser('segmentsubmit');
        insert new Leave_Balance__c(
            User__c = employee.Id,
            Year__c = 2026,
            Annual_Leave__c = 2,
            Sick_Leave__c = 0,
            Personal_Leave__c = 0
        );
        insert new Leave_Balance__c(
            User__c = employee.Id,
            Year__c = 2027,
            Annual_Leave__c = 3,
            Sick_Leave__c = 0,
            Personal_Leave__c = 0
        );

        Leave_Request__c requestRecord = new Leave_Request__c(
            Employee__c = employee.Id,
            Leave_Type__c = 'Annual',
            Start_Date__c = Date.newInstance(2026, 12, 30),
            End_Date__c = Date.newInstance(2027, 1, 3),
            Status__c = 'Draft',
            Balance_Deducted__c = false
        );
        insert requestRecord;

        requestRecord.Status__c = 'Submitted';

        Test.startTest();
        update requestRecord;
        Test.stopTest();

        List<Leave_Request_Segment__c> segments = [
            SELECT Segment_Start_Date__c, Segment_End_Date__c, Balance_Year__c, Days__c, Segment_Status__c
            FROM Leave_Request_Segment__c
            WHERE Leave_Request__c = :requestRecord.Id
            ORDER BY Segment_Start_Date__c
        ];

        Assert.areEqual(2, segments.size(), 'Should persist two segments for cross-year leave request.');
        Assert.areEqual(2026, Integer.valueOf(String.valueOf(segments[0].Balance_Year__c)));
        Assert.areEqual(2, segments[0].Days__c);
        Assert.areEqual('Reserved', segments[0].Segment_Status__c);
        Assert.areEqual(2027, Integer.valueOf(String.valueOf(segments[1].Balance_Year__c)));
        Assert.areEqual(3, segments[1].Days__c);
        Assert.areEqual('Reserved', segments[1].Segment_Status__c);
    }

    @IsTest
    static void testCrossYearDeductionConsumesBothYears() {
        User employee = createEmployeeUser('segmentdeduct');
        insert new Leave_Balance__c(
            User__c = employee.Id,
            Year__c = 2026,
            Annual_Leave__c = 2,
            Sick_Leave__c = 0,
            Personal_Leave__c = 0
        );
        insert new Leave_Balance__c(
            User__c = employee.Id,
            Year__c = 2027,
            Annual_Leave__c = 3,
            Sick_Leave__c = 0,
            Personal_Leave__c = 0
        );

        Leave_Request__c requestRecord = new Leave_Request__c(
            Employee__c = employee.Id,
            Leave_Type__c = 'Annual',
            Start_Date__c = Date.newInstance(2026, 12, 30),
            End_Date__c = Date.newInstance(2027, 1, 3),
            Status__c = 'Approved',
            Balance_Deducted__c = false
        );
        insert requestRecord;

        Test.startTest();
        LeaveService.deductBalance(requestRecord.Id);
        Test.stopTest();

        Map<Integer, Leave_Balance__c> balancesByYear = new Map<Integer, Leave_Balance__c>();
        for (Leave_Balance__c balance : [
            SELECT Year__c, Annual_Leave__c
            FROM Leave_Balance__c
            WHERE User__c = :employee.Id
            AND Year__c IN (2026, 2027)
        ]) {
            balancesByYear.put(Integer.valueOf(String.valueOf(balance.Year__c)), balance);
        }

        Assert.areEqual(0, balancesByYear.get(2026).Annual_Leave__c, '2026 balance should be fully consumed.');
        Assert.areEqual(0, balancesByYear.get(2027).Annual_Leave__c, '2027 balance should be fully consumed.');
    }

    private static User createEmployeeUser(String key) {
        User currentUser = [
            SELECT ProfileId
            FROM User
            WHERE Id = :UserInfo.getUserId()
        ];
        String uniqueToken = key + String.valueOf(DateTime.now().getTime());
        User employee = new User(
            Alias = uniqueToken.substring(0, Math.min(8, uniqueToken.length())),
            Email = uniqueToken + '@example.com',
            EmailEncodingKey = 'UTF-8',
            LastName = 'Employee',
            LanguageLocaleKey = 'en_US',
            LocaleSidKey = 'en_US',
            ProfileId = currentUser.ProfileId,
            TimeZoneSidKey = 'America/Los_Angeles',
            Username = uniqueToken + '@example.com',
            ManagerId = UserInfo.getUserId()
        );
        insert employee;
        return employee;
    }
}
