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
            Approval_Mode__c = 'Manager Then HR',
            Auto_Approve_Below_Days__c = 1,
            Escalate_Above_Days__c = 5,
            Escalation_Target__c = 'HR',
            Approval_Group_Key__c = 'HR_QUEUE',
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
        Assert.areEqual('Manager Then HR', policy.approvalMode);
        Assert.areEqual(1, policy.autoApproveBelowDays);
        Assert.areEqual(5, policy.escalateAboveDays);
        Assert.areEqual('HR', policy.escalationTarget);
        Assert.areEqual('HR_QUEUE', policy.approvalGroupKey);
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
        User employee = createEmployeeUser('policyinactive');

        Leave_Type_Definition__c personalDefinition = new Leave_Type_Definition__c(
            Name = 'Personal Leave Policy',
            Type_Code__c = 'PERSONAL',
            Is_Active__c = false,
            Allow_Carryover__c = false,
            Policy_Version__c = 5
        );
        insert personalDefinition;
        insert new Leave_Balance__c(
            User__c = employee.Id,
            Year__c = yearValue,
            Annual_Leave__c = 10,
            Sick_Leave__c = 10,
            Personal_Leave__c = 10
        );

        Leave_Request__c requestRecord = new Leave_Request__c(
            Employee__c = employee.Id,
            Leave_Type_Definition__c = personalDefinition.Id,
            Start_Date__c = Date.today().addDays(5),
            End_Date__c = Date.today().addDays(6),
            Status__c = 'Draft',
            Balance_Deducted__c = false
        );
        insert requestRecord;

        Leave_Request__c insertedRequest = [
            SELECT Start_Date__c, End_Date__c, Employee__c, Status__c,
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

    @IsTest
    static void testSubmissionUsesApprovalPolicyRouting() {
        Integer yearValue = Date.today().year();
        User employee = createEmployeeUser('policyroute');

        Leave_Type_Definition__c annualDefinition = new Leave_Type_Definition__c(
            Name = 'Annual Leave Policy',
            Type_Code__c = 'ANNUAL',
            Is_Active__c = true,
            Allow_Carryover__c = true,
            Approval_Mode__c = 'Manager Then HR',
            Approval_Group_Key__c = 'HR_QUEUE',
            Policy_Version__c = 7
        );
        insert annualDefinition;
        insert new Leave_Balance__c(
            User__c = employee.Id,
            Year__c = yearValue,
            Annual_Leave__c = 10,
            Sick_Leave__c = 10,
            Personal_Leave__c = 10
        );

        Leave_Request__c requestRecord = new Leave_Request__c(
            Employee__c = employee.Id,
            Leave_Type_Definition__c = annualDefinition.Id,
            Start_Date__c = Date.today().addDays(3),
            End_Date__c = Date.today().addDays(4),
            Status__c = 'Draft',
            Balance_Deducted__c = false
        );
        insert requestRecord;

        requestRecord.Status__c = 'Submitted';
        update requestRecord;

        Leave_Request__c submittedRequest = [
            SELECT Status__c, Manager__c, Approval_Mode_Snapshot__c, Approval_Target_Snapshot__c
            FROM Leave_Request__c
            WHERE Id = :requestRecord.Id
        ];
        Assert.areEqual('Pending_Manager_Approval', submittedRequest.Status__c);
        Assert.areEqual(UserInfo.getUserId(), submittedRequest.Manager__c);
        Assert.areEqual('Manager Then HR', submittedRequest.Approval_Mode_Snapshot__c);
        Assert.areEqual('HR_QUEUE', submittedRequest.Approval_Target_Snapshot__c);

        List<Leave_Approval_History__c> submittedHistories = [
            SELECT Stage__c, Action__c, Approver__c, Approver_Target__c, Approval_Mode_Snapshot__c
            FROM Leave_Approval_History__c
            WHERE Leave_Request__c = :requestRecord.Id
            ORDER BY CreatedDate
        ];
        Assert.areEqual(1, submittedHistories.size());
        Assert.areEqual('Submit', submittedHistories[0].Stage__c);
        Assert.areEqual('Submitted', submittedHistories[0].Action__c);
        Assert.areEqual(UserInfo.getUserId(), submittedHistories[0].Approver__c);
        Assert.areEqual('Manager', submittedHistories[0].Approver_Target__c);
        Assert.areEqual('Manager Then HR', submittedHistories[0].Approval_Mode_Snapshot__c);

        submittedRequest.Status__c = 'Approved';
        update submittedRequest;

        Leave_Request__c escalatedRequest = [
            SELECT Status__c
            FROM Leave_Request__c
            WHERE Id = :requestRecord.Id
        ];
        Assert.areEqual('Pending_HR_Approval', escalatedRequest.Status__c);

        List<Leave_Approval_History__c> managerApprovedHistories = [
            SELECT Stage__c, Action__c, Approver_Target__c
            FROM Leave_Approval_History__c
            WHERE Leave_Request__c = :requestRecord.Id
            ORDER BY CreatedDate
        ];
        Assert.areEqual(2, managerApprovedHistories.size());
        Assert.areEqual('Manager_Approval', managerApprovedHistories[1].Stage__c);
        Assert.areEqual('Approved', managerApprovedHistories[1].Action__c);
        Assert.areEqual('Manager', managerApprovedHistories[1].Approver_Target__c);

        escalatedRequest.Status__c = 'Approved';
        update escalatedRequest;

        List<Leave_Approval_History__c> finalHistories = [
            SELECT Stage__c, Action__c, Approver_Target__c
            FROM Leave_Approval_History__c
            WHERE Leave_Request__c = :requestRecord.Id
            ORDER BY CreatedDate
        ];
        Assert.areEqual(3, finalHistories.size());
        Assert.areEqual('HR_Approval', finalHistories[2].Stage__c);
        Assert.areEqual('Approved', finalHistories[2].Action__c);
        Assert.areEqual('HR_QUEUE', finalHistories[2].Approver_Target__c);
    }

    @IsTest
    static void testConfigurablePolicyCanAutoApprove() {
        Integer yearValue = Date.today().year();
        User employee = createEmployeeUser('policyauto');

        Leave_Type_Definition__c sickDefinition = new Leave_Type_Definition__c(
            Name = 'Sick Leave Policy',
            Type_Code__c = 'SICK',
            Is_Active__c = true,
            Allow_Carryover__c = false,
            Approval_Mode__c = 'Configurable',
            Auto_Approve_Below_Days__c = 1,
            Policy_Version__c = 2
        );
        insert sickDefinition;
        insert new Leave_Balance__c(
            User__c = employee.Id,
            Year__c = yearValue,
            Annual_Leave__c = 10,
            Sick_Leave__c = 10,
            Personal_Leave__c = 10
        );

        Leave_Request__c requestRecord = new Leave_Request__c(
            Employee__c = employee.Id,
            Leave_Type_Definition__c = sickDefinition.Id,
            Start_Date__c = Date.today().addDays(10),
            End_Date__c = Date.today().addDays(10),
            Status__c = 'Draft',
            Balance_Deducted__c = false
        );
        insert requestRecord;

        requestRecord.Status__c = 'Submitted';
        update requestRecord;

        Leave_Request__c approvedRequest = [
            SELECT Status__c, Approval_Mode_Snapshot__c, Approval_Target_Snapshot__c, Balance_Deducted__c
            FROM Leave_Request__c
            WHERE Id = :requestRecord.Id
        ];
        Assert.areEqual('Approved', approvedRequest.Status__c);
        Assert.areEqual('Auto Approve', approvedRequest.Approval_Mode_Snapshot__c);
        Assert.areEqual('Auto', approvedRequest.Approval_Target_Snapshot__c);
        Assert.areEqual(true, approvedRequest.Balance_Deducted__c);

        List<Leave_Approval_History__c> histories = [
            SELECT Stage__c, Action__c, Approver_Target__c, Approval_Mode_Snapshot__c
            FROM Leave_Approval_History__c
            WHERE Leave_Request__c = :requestRecord.Id
            ORDER BY CreatedDate
        ];
        Assert.areEqual(2, histories.size());
        Assert.areEqual('Submitted', histories[0].Action__c);
        Assert.areEqual('Auto', histories[0].Approver_Target__c);
        Assert.areEqual('Approved', histories[1].Action__c);
        Assert.areEqual('Auto', histories[1].Approver_Target__c);
        Assert.areEqual('Auto Approve', histories[1].Approval_Mode_Snapshot__c);
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
