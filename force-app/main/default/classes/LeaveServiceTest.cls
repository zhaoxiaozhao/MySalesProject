@IsTest
private class LeaveServiceTest {

    @IsTest
    static void testRejectLeaveUsesHrStageHistory() {
        User employee = createEmployeeUser('rejecthr');
        Integer yearValue = Date.today().year();

        insert new Leave_Balance__c(
            User__c = employee.Id,
            Year__c = yearValue,
            Annual_Leave__c = 10,
            Sick_Leave__c = 5,
            Personal_Leave__c = 5
        );

        Leave_Request__c requestRecord = new Leave_Request__c(
            Employee__c = employee.Id,
            Manager__c = UserInfo.getUserId(),
            Leave_Type__c = 'Annual',
            Start_Date__c = Date.today().addDays(5),
            End_Date__c = Date.today().addDays(6),
            Status__c = 'Pending_HR_Approval',
            Balance_Deducted__c = false,
            Approval_Mode_Snapshot__c = 'HR Only',
            Approval_Target_Snapshot__c = 'HR_QUEUE'
        );
        insert requestRecord;

        Test.startTest();
        LeaveService.rejectLeave(requestRecord.Id, UserInfo.getUserId(), 'Rejected by HR');
        Test.stopTest();

        Leave_Request__c updatedRequest = [
            SELECT Status__c
            FROM Leave_Request__c
            WHERE Id = :requestRecord.Id
        ];
        Leave_Approval_History__c history = [
            SELECT Stage__c, Action__c, Approver__c, Approver_Target__c, Comments__c
            FROM Leave_Approval_History__c
            WHERE Leave_Request__c = :requestRecord.Id
            ORDER BY CreatedDate DESC
            LIMIT 1
        ];

        Assert.areEqual('Rejected', updatedRequest.Status__c);
        Assert.areEqual('HR_Approval', history.Stage__c);
        Assert.areEqual('Rejected', history.Action__c);
        Assert.areEqual(UserInfo.getUserId(), history.Approver__c);
        Assert.areEqual('HR_QUEUE', history.Approver_Target__c);
        Assert.areEqual('Rejected by HR', history.Comments__c);
    }

    @IsTest
    static void testSubmitLeaveHrOnlySkipsApprovalProcessAndCreatesSubmittedHistory() {
        User employee = createEmployeeUser('submithr');
        Integer yearValue = Date.today().year();

        insert new Leave_Type_Definition__c(
            Name = 'Annual Leave HR Policy',
            Type_Code__c = 'ANNUAL',
            Is_Active__c = true,
            Allow_Carryover__c = true,
            Approval_Mode__c = 'HR Only',
            Approval_Group_Key__c = 'HR_QUEUE',
            Policy_Version__c = 11
        );
        insert new Leave_Balance__c(
            User__c = employee.Id,
            Year__c = yearValue,
            Annual_Leave__c = 10,
            Sick_Leave__c = 5,
            Personal_Leave__c = 5
        );

        Leave_Request__c requestRecord = new Leave_Request__c(
            Employee__c = employee.Id,
            Leave_Type__c = 'Annual',
            Start_Date__c = Date.today().addDays(9),
            End_Date__c = Date.today().addDays(10),
            Status__c = 'Draft',
            Balance_Deducted__c = false
        );
        insert requestRecord;

        Test.startTest();
        LeaveService.submitLeave(requestRecord.Id);
        Test.stopTest();

        Leave_Request__c submittedRequest = [
            SELECT Status__c, Manager__c, Submitted_Time__c, Approval_Mode_Snapshot__c, Approval_Target_Snapshot__c
            FROM Leave_Request__c
            WHERE Id = :requestRecord.Id
        ];
        List<Leave_Approval_History__c> histories = [
            SELECT Stage__c, Action__c, Approver__c, Approver_Target__c, Approval_Mode_Snapshot__c
            FROM Leave_Approval_History__c
            WHERE Leave_Request__c = :requestRecord.Id
            ORDER BY CreatedDate
        ];
        List<ProcessInstance> instances = [
            SELECT Id, Status, TargetObjectId
            FROM ProcessInstance
            WHERE TargetObjectId = :requestRecord.Id
        ];

        Assert.areEqual('Pending_HR_Approval', submittedRequest.Status__c);
        Assert.areEqual(UserInfo.getUserId(), submittedRequest.Manager__c);
        Assert.isNotNull(submittedRequest.Submitted_Time__c);
        Assert.areEqual('HR Only', submittedRequest.Approval_Mode_Snapshot__c);
        Assert.areEqual('HR_QUEUE', submittedRequest.Approval_Target_Snapshot__c);
        Assert.areEqual(1, histories.size(), 'HR-only submission should create one submitted history.');
        Assert.areEqual('Submit', histories[0].Stage__c);
        Assert.areEqual('Submitted', histories[0].Action__c);
        Assert.areEqual(null, histories[0].Approver__c);
        Assert.areEqual('HR_QUEUE', histories[0].Approver_Target__c);
        Assert.areEqual('HR Only', histories[0].Approval_Mode_Snapshot__c);
        Assert.areEqual(0, instances.size(), 'HR-only submit should not create approval process instances.');
    }

    @IsTest
    static void testSubmitLeaveAutoApproveSkipsApprovalProcessAndWritesTwoHistories() {
        User employee = createEmployeeUser('submitauto');
        Integer yearValue = Date.today().year();

        insert new Leave_Type_Definition__c(
            Name = 'Sick Leave Auto Policy',
            Type_Code__c = 'SICK',
            Is_Active__c = true,
            Allow_Carryover__c = false,
            Approval_Mode__c = 'Configurable',
            Auto_Approve_Below_Days__c = 1,
            Policy_Version__c = 6
        );
        insert new Leave_Balance__c(
            User__c = employee.Id,
            Year__c = yearValue,
            Annual_Leave__c = 10,
            Sick_Leave__c = 5,
            Personal_Leave__c = 5
        );

        Leave_Request__c requestRecord = new Leave_Request__c(
            Employee__c = employee.Id,
            Leave_Type__c = 'Sick',
            Start_Date__c = Date.today().addDays(12),
            End_Date__c = Date.today().addDays(12),
            Status__c = 'Draft',
            Balance_Deducted__c = false
        );
        insert requestRecord;

        Test.startTest();
        LeaveService.submitLeave(requestRecord.Id);
        Test.stopTest();

        Leave_Request__c approvedRequest = [
            SELECT Status__c, Balance_Deducted__c, Approval_Mode_Snapshot__c, Approval_Target_Snapshot__c
            FROM Leave_Request__c
            WHERE Id = :requestRecord.Id
        ];
        Leave_Balance__c balance = [
            SELECT Sick_Leave__c
            FROM Leave_Balance__c
            WHERE User__c = :employee.Id
            AND Year__c = :yearValue
            LIMIT 1
        ];
        List<Leave_Approval_History__c> histories = [
            SELECT Stage__c, Action__c, Approver__c, Approver_Target__c, Approval_Mode_Snapshot__c, Comments__c
            FROM Leave_Approval_History__c
            WHERE Leave_Request__c = :requestRecord.Id
            ORDER BY CreatedDate
        ];
        List<ProcessInstance> instances = [
            SELECT Id
            FROM ProcessInstance
            WHERE TargetObjectId = :requestRecord.Id
        ];

        Assert.areEqual('Approved', approvedRequest.Status__c);
        Assert.areEqual(true, approvedRequest.Balance_Deducted__c);
        Assert.areEqual('Auto Approve', approvedRequest.Approval_Mode_Snapshot__c);
        Assert.areEqual('Auto', approvedRequest.Approval_Target_Snapshot__c);
        Assert.areEqual(4, balance.Sick_Leave__c, 'Auto approved submit should still deduct balance once.');
        Assert.areEqual(2, histories.size(), 'Auto approve submit should create submitted and approved histories.');
        Assert.areEqual('Submitted', histories[0].Action__c);
        Assert.areEqual('Auto', histories[0].Approver_Target__c);
        Assert.areEqual(null, histories[0].Approver__c);
        Assert.areEqual('Approved', histories[1].Action__c);
        Assert.areEqual('Auto', histories[1].Approver_Target__c);
        Assert.areEqual('Auto approved by policy.', histories[1].Comments__c);
        Assert.areEqual(0, instances.size(), 'Auto approve submit should not create approval process instances.');
    }

    @IsTest
    static void testRejectLeaveRejectsInvalidStatus() {
        User employee = createEmployeeUser('rejectinvalid');

        Leave_Request__c requestRecord = new Leave_Request__c(
            Employee__c = employee.Id,
            Leave_Type__c = 'Annual',
            Start_Date__c = Date.today().addDays(4),
            End_Date__c = Date.today().addDays(4),
            Status__c = 'Draft',
            Balance_Deducted__c = false
        );
        insert requestRecord;

        try {
            LeaveService.rejectLeave(requestRecord.Id, UserInfo.getUserId(), 'Should fail');
            Assert.fail('Draft leave should not be rejectable.');
        } catch (IllegalArgumentException ex) {
            Assert.isTrue(ex.getMessage().contains('rejectable'));
        }
    }

    @IsTest
    static void testApproveLeaveRejectsInvalidStatus() {
        User employee = createEmployeeUser('invalidapprove');
        Integer yearValue = Date.today().year();

        insert new Leave_Balance__c(
            User__c = employee.Id,
            Year__c = yearValue,
            Annual_Leave__c = 10,
            Sick_Leave__c = 5,
            Personal_Leave__c = 5
        );

        Leave_Request__c requestRecord = new Leave_Request__c(
            Employee__c = employee.Id,
            Leave_Type__c = 'Annual',
            Start_Date__c = Date.today().addDays(2),
            End_Date__c = Date.today().addDays(2),
            Status__c = 'Draft',
            Balance_Deducted__c = false
        );
        insert requestRecord;

        try {
            LeaveService.approveLeave(requestRecord.Id, UserInfo.getUserId(), 'Should fail');
            Assert.fail('Draft leave should not be approvable.');
        } catch (IllegalArgumentException ex) {
            Assert.isTrue(ex.getMessage().contains('approvable'));
        }
    }

    @IsTest
    static void testApproveLeaveManagerStageEscalatesToHrWithoutDeductingBalance() {
        User employee = createEmployeeUser('approveescalate');
        Integer yearValue = Date.today().year();

        insert new Leave_Balance__c(
            User__c = employee.Id,
            Year__c = yearValue,
            Annual_Leave__c = 10,
            Sick_Leave__c = 5,
            Personal_Leave__c = 5
        );

        Leave_Request__c requestRecord = new Leave_Request__c(
            Employee__c = employee.Id,
            Manager__c = UserInfo.getUserId(),
            Leave_Type__c = 'Annual',
            Start_Date__c = Date.today().addDays(7),
            End_Date__c = Date.today().addDays(8),
            Status__c = 'Pending_Manager_Approval',
            Balance_Deducted__c = false,
            Approval_Mode_Snapshot__c = 'Manager Then HR',
            Approval_Target_Snapshot__c = 'HR_QUEUE'
        );
        insert requestRecord;

        Test.startTest();
        LeaveService.approveLeave(requestRecord.Id, UserInfo.getUserId(), 'Approved by manager');
        Test.stopTest();

        Leave_Request__c escalatedRequest = [
            SELECT Status__c, Balance_Deducted__c
            FROM Leave_Request__c
            WHERE Id = :requestRecord.Id
        ];
        Leave_Balance__c balance = [
            SELECT Annual_Leave__c
            FROM Leave_Balance__c
            WHERE User__c = :employee.Id
            AND Year__c = :yearValue
            LIMIT 1
        ];
        Leave_Approval_History__c history = [
            SELECT Stage__c, Action__c, Approver__c, Approver_Target__c, Comments__c
            FROM Leave_Approval_History__c
            WHERE Leave_Request__c = :requestRecord.Id
            ORDER BY CreatedDate DESC
            LIMIT 1
        ];

        Assert.areEqual('Pending_HR_Approval', escalatedRequest.Status__c);
        Assert.areEqual(false, escalatedRequest.Balance_Deducted__c);
        Assert.areEqual(10, balance.Annual_Leave__c, 'Manager approval should not deduct balance before HR approval.');
        Assert.areEqual('Manager_Approval', history.Stage__c);
        Assert.areEqual('Approved', history.Action__c);
        Assert.areEqual(UserInfo.getUserId(), history.Approver__c);
        Assert.areEqual('Manager', history.Approver_Target__c);
        Assert.areEqual('Approved by manager', history.Comments__c);
    }

    @IsTest
    static void testValidateBalanceThrowsWhenExistingUsageConsumesRemainingDays() {
        User employee = createEmployeeUser('balanceusage');
        Integer yearValue = Date.today().year();

        insert new Leave_Balance__c(
            User__c = employee.Id,
            Year__c = yearValue,
            Annual_Leave__c = 5,
            Sick_Leave__c = 5,
            Personal_Leave__c = 5
        );

        Leave_Request__c existingRequest = new Leave_Request__c(
            Employee__c = employee.Id,
            Leave_Type__c = 'Sick',
            Start_Date__c = Date.today().addDays(1),
            End_Date__c = Date.today().addDays(3),
            Status__c = 'Approved',
            Balance_Deducted__c = false
        );
        insert existingRequest;

        Leave_Request__c editedRequest = new Leave_Request__c(
            Employee__c = employee.Id,
            Leave_Type__c = 'Sick',
            Start_Date__c = Date.today().addDays(10),
            End_Date__c = Date.today().addDays(10),
            Status__c = 'Draft',
            Balance_Deducted__c = false
        );
        insert editedRequest;

        try {
            LeaveService.validateBalance(
                employee.Id,
                'Sick',
                3,
                Date.today().addDays(10),
                Date.today().addDays(12),
                editedRequest.Id
            );
            Assert.fail('Existing approved usage should reduce the remaining balance.');
        } catch (IllegalArgumentException ex) {
            Assert.isTrue(ex.getMessage().contains('Insufficient Sick balance'));
        }
    }

    @IsTest
    static void testDeductBalanceUpdatesSickAndPersonalBalances() {
        User employee = createEmployeeUser('otherdeduct');
        Integer yearValue = Date.today().year();

        insert new Leave_Balance__c(
            User__c = employee.Id,
            Year__c = yearValue,
            Annual_Leave__c = 10,
            Sick_Leave__c = 5,
            Personal_Leave__c = 4
        );

        Leave_Request__c sickRequest = new Leave_Request__c(
            Employee__c = employee.Id,
            Leave_Type__c = 'Sick',
            Start_Date__c = Date.today().addDays(15),
            End_Date__c = Date.today().addDays(16),
            Status__c = 'Approved',
            Balance_Deducted__c = false
        );
        Leave_Request__c personalRequest = new Leave_Request__c(
            Employee__c = employee.Id,
            Leave_Type__c = 'Personal',
            Start_Date__c = Date.today().addDays(20),
            End_Date__c = Date.today().addDays(20),
            Status__c = 'Approved',
            Balance_Deducted__c = false
        );
        insert new List<Leave_Request__c>{ sickRequest, personalRequest };

        Test.startTest();
        LeaveService.deductBalance(sickRequest.Id);
        LeaveService.deductBalance(personalRequest.Id);
        LeaveService.handleApprovalResult(personalRequest.Id, false);
        Test.stopTest();

        Leave_Balance__c updatedBalance = [
            SELECT Sick_Leave__c, Personal_Leave__c
            FROM Leave_Balance__c
            WHERE User__c = :employee.Id
            AND Year__c = :yearValue
            LIMIT 1
        ];

        Assert.areEqual(3, updatedBalance.Sick_Leave__c);
        Assert.areEqual(3, updatedBalance.Personal_Leave__c);
    }

    @IsTest
    static void testValidateBalanceThrowsWhenNoBalanceExists() {
        User employee = createEmployeeUser('nobalance');

        try {
            LeaveService.validateBalance(
                employee.Id,
                'Annual',
                1,
                Date.today().addDays(1),
                Date.today().addDays(1),
                null
            );
            Assert.fail('Employee without balance should be blocked.');
        } catch (IllegalArgumentException ex) {
            Assert.isTrue(ex.getMessage().contains('No leave balance found'));
        }
    }

    @IsTest
    static void testValidateBalanceThrowsWhenAnnualBalanceMissingForSegmentYear() {
        User employee = createEmployeeUser('missingyear');
        Integer currentYear = Date.today().year();
        Integer nextYear = currentYear + 1;

        insert new Leave_Balance__c(
            User__c = employee.Id,
            Year__c = currentYear,
            Annual_Leave__c = 5,
            Sick_Leave__c = 5,
            Personal_Leave__c = 5
        );

        try {
            LeaveService.validateBalance(
                employee.Id,
                'Annual',
                3,
                Date.newInstance(currentYear, 12, 31),
                Date.newInstance(nextYear, 1, 2),
                null
            );
            Assert.fail('Cross-year annual leave should require a balance in each segment year.');
        } catch (IllegalArgumentException ex) {
            Assert.isTrue(
                ex.getMessage().contains('year ' + String.valueOf(nextYear)),
                'Should mention the missing target year balance.'
            );
        }
    }

    @IsTest
    static void testHasOverlappingDatesReturnsTrueAndFalseByStatus() {
        User employee = createEmployeeUser('overlap');

        Leave_Request__c approvedRequest = new Leave_Request__c(
            Employee__c = employee.Id,
            Leave_Type__c = 'Annual',
            Start_Date__c = Date.today().addDays(8),
            End_Date__c = Date.today().addDays(10),
            Status__c = 'Approved',
            Balance_Deducted__c = false
        );
        Leave_Request__c draftRequest = new Leave_Request__c(
            Employee__c = employee.Id,
            Leave_Type__c = 'Annual',
            Start_Date__c = Date.today().addDays(20),
            End_Date__c = Date.today().addDays(22),
            Status__c = 'Draft',
            Balance_Deducted__c = false
        );
        insert new List<Leave_Request__c>{ approvedRequest, draftRequest };

        Boolean overlapsApproved = LeaveService.hasOverlappingDates(
            employee.Id,
            Date.today().addDays(9),
            Date.today().addDays(11),
            null
        );
        Boolean overlapsDraftOnly = LeaveService.hasOverlappingDates(
            employee.Id,
            Date.today().addDays(21),
            Date.today().addDays(21),
            null
        );
        Boolean excludesCurrentRequest = LeaveService.hasOverlappingDates(
            employee.Id,
            Date.today().addDays(8),
            Date.today().addDays(10),
            approvedRequest.Id
        );

        Assert.areEqual(true, overlapsApproved, 'Approved request should be treated as overlapping.');
        Assert.areEqual(false, overlapsDraftOnly, 'Draft request should not count as effective overlap.');
        Assert.areEqual(false, excludesCurrentRequest, 'Excluded request should not block itself.');
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
