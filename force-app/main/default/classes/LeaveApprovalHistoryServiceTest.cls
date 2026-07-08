@IsTest
private class LeaveApprovalHistoryServiceTest {

    @IsTest
    static void testCreateTransitionHistoriesAddsSubmittedAndAutoApprovedEntries() {
        User employee = createEmployeeUser('autohistory');
        Integer yearValue = Date.today().year();

        insert new Leave_Balance__c(
            User__c = employee.Id,
            Year__c = yearValue,
            Annual_Leave__c = 10,
            Sick_Leave__c = 10,
            Personal_Leave__c = 10
        );

        Leave_Request__c requestRecord = new Leave_Request__c(
            Employee__c = employee.Id,
            Leave_Type__c = 'Sick',
            Start_Date__c = Date.today().addDays(3),
            End_Date__c = Date.today().addDays(3),
            Status__c = 'Draft',
            Balance_Deducted__c = false
        );
        insert requestRecord;

        Leave_Request__c updatedRequest = new Leave_Request__c(
            Id = requestRecord.Id,
            Employee__c = employee.Id,
            Manager__c = UserInfo.getUserId(),
            Status__c = 'Approved',
            Approval_Mode_Snapshot__c = 'Auto Approve',
            Approval_Target_Snapshot__c = 'Auto'
        );
        Map<Id, Leave_Request__c> oldMap = new Map<Id, Leave_Request__c>{
            requestRecord.Id => new Leave_Request__c(
                Id = requestRecord.Id,
                Status__c = 'Draft'
            )
        };

        Test.startTest();
        LeaveApprovalHistoryService.createTransitionHistories(
            new List<Leave_Request__c>{ updatedRequest },
            oldMap
        );
        Test.stopTest();

        List<Leave_Approval_History__c> histories = [
            SELECT Stage__c, Action__c, Approver__c, Approver_Target__c,
                   Approval_Mode_Snapshot__c, Comments__c
            FROM Leave_Approval_History__c
            WHERE Leave_Request__c = :requestRecord.Id
            ORDER BY CreatedDate
        ];

        Assert.areEqual(2, histories.size());
        Assert.areEqual('Submit', histories[0].Stage__c);
        Assert.areEqual('Submitted', histories[0].Action__c);
        Assert.areEqual('Auto', histories[0].Approver_Target__c);
        Assert.areEqual('Auto Approve', histories[0].Approval_Mode_Snapshot__c);
        Assert.areEqual(null, histories[0].Approver__c);
        Assert.areEqual('Submit', histories[1].Stage__c);
        Assert.areEqual('Approved', histories[1].Action__c);
        Assert.areEqual('Auto', histories[1].Approver_Target__c);
        Assert.areEqual('Auto approved by policy.', histories[1].Comments__c);
    }

    @IsTest
    static void testLeaveExpiryBatchWritesCancellationHistory() {
        User employee = createEmployeeUser('expiryhistory');

        Leave_Request__c requestRecord = new Leave_Request__c(
            Employee__c = employee.Id,
            Manager__c = UserInfo.getUserId(),
            Leave_Type__c = 'Annual',
            Start_Date__c = Date.today().addDays(-5),
            End_Date__c = Date.today().addDays(-2),
            Status__c = 'Pending_HR_Approval',
            Balance_Deducted__c = false,
            Approval_Mode_Snapshot__c = 'Manager Then HR',
            Approval_Target_Snapshot__c = 'HR_QUEUE',
            Reason__c = 'Initial reason'
        );
        insert requestRecord;

        Test.startTest();
        Database.executeBatch(new LeaveExpiryBatch(), 50);
        Test.stopTest();

        Leave_Request__c cancelledRequest = [
            SELECT Status__c, Reason__c
            FROM Leave_Request__c
            WHERE Id = :requestRecord.Id
        ];
        Leave_Approval_History__c history = [
            SELECT Stage__c, Action__c, Approver__c, Approver_Target__c,
                   Approval_Mode_Snapshot__c, Comments__c
            FROM Leave_Approval_History__c
            WHERE Leave_Request__c = :requestRecord.Id
            ORDER BY CreatedDate DESC
            LIMIT 1
        ];

        Assert.areEqual('Cancelled', cancelledRequest.Status__c);
        Assert.isTrue(cancelledRequest.Reason__c.contains('Auto-cancelled: leave period ended'));
        Assert.areEqual('Cancellation', history.Stage__c);
        Assert.areEqual('Cancelled', history.Action__c);
        Assert.areEqual(null, history.Approver__c);
        Assert.areEqual('HR_QUEUE', history.Approver_Target__c);
        Assert.areEqual('Manager Then HR', history.Approval_Mode_Snapshot__c);
        Assert.areEqual('Auto-cancelled by system: leave period expired without approval', history.Comments__c);
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
