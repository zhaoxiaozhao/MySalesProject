@IsTest
private class LeaveHomeControllerTest {

    @IsTest
    static void testGetUserRolesUsesDirectReportFallback() {
        User manager = createUser('managerrole');
        User employee = createUser('employeerole');
        employee.ManagerId = manager.Id;
        update employee;

        System.runAs(manager) {
            LeaveHomeController.RoleInfo info = LeaveHomeController.getUserRoles();
            Assert.areEqual(true, info.isManager);
            Assert.areEqual(true, info.isEmployee);
            Assert.areEqual(false, info.isHR);
        }
    }

    @IsTest
    static void testGetHrPendingApprovalsReturnsPendingHrRecords() {
        User employee = createUser('hrpendingemp');
        Integer yearValue = Date.today().year();
        Leave_Type_Definition__c annualDefinition = createLeaveTypeDefinition(
            'ANNUAL',
            'Annual Leave Policy'
        );

        insert new Leave_Balance__c(
            User__c = employee.Id,
            Year__c = yearValue,
            Annual_Leave__c = 10,
            Sick_Leave__c = 5,
            Personal_Leave__c = 5
        );

        Leave_Request__c pendingHr = new Leave_Request__c(
            Employee__c = employee.Id,
            Manager__c = UserInfo.getUserId(),
            Leave_Type_Definition__c = annualDefinition.Id,
            Start_Date__c = Date.today().addDays(3),
            End_Date__c = Date.today().addDays(4),
            Status__c = 'Pending_HR_Approval',
            Balance_Deducted__c = false,
            Approval_Mode_Snapshot__c = 'HR Only',
            Approval_Target_Snapshot__c = UserInfo.getUserId()
        );
        Leave_Request__c draftRequest = new Leave_Request__c(
            Employee__c = employee.Id,
            Leave_Type_Definition__c = annualDefinition.Id,
            Start_Date__c = Date.today().addDays(6),
            End_Date__c = Date.today().addDays(6),
            Status__c = 'Draft',
            Balance_Deducted__c = false
        );
        insert new List<Leave_Request__c>{ pendingHr, draftRequest };

        List<Leave_Request__c> hrPending = LeaveHomeController.getHrPendingApprovals();

        Assert.areEqual(1, hrPending.size());
        Assert.areEqual(pendingHr.Id, hrPending[0].Id);
    }

    @IsTest
    static void testGetAvailableLeaveTypesReturnsOnlyActiveSupportedDefinitions() {
        createLeaveTypeDefinition('ANNUAL', 'Annual Leave Policy');
        createLeaveTypeDefinition('SICK', 'Sick Leave Policy');
        insert new Leave_Type_Definition__c(
            Name = 'Study Leave Policy',
            Type_Code__c = 'STUDY',
            Is_Active__c = true,
            Policy_Version__c = 1
        );
        insert new Leave_Type_Definition__c(
            Name = 'Inactive Personal Policy',
            Type_Code__c = 'PERSONAL',
            Is_Active__c = false,
            Policy_Version__c = 1
        );

        List<LeaveHomeController.LeaveTypeOption> options =
            LeaveHomeController.getAvailableLeaveTypes();

        Assert.areEqual(2, options.size());
        Set<String> typeCodes = new Set<String>();
        for (LeaveHomeController.LeaveTypeOption option : options) {
            typeCodes.add(option.typeCode);
        }
        Assert.areEqual(true, typeCodes.contains('ANNUAL'));
        Assert.areEqual(true, typeCodes.contains('SICK'));
        Assert.areEqual(false, typeCodes.contains('STUDY'));
        Assert.areEqual(false, typeCodes.contains('PERSONAL'));
    }

    @IsTest
    static void testCreateLeaveRequestCreatesDraftWithDefinitionSnapshot() {
        Leave_Type_Definition__c annualDefinition = createLeaveTypeDefinition(
            'ANNUAL',
            'Annual Leave Policy'
        );

        Test.startTest();
        Id requestId = LeaveHomeController.createLeaveRequest(
            annualDefinition.Id,
            Date.today().addDays(2),
            Date.today().addDays(4),
            'Family trip'
        );
        Test.stopTest();

        Leave_Request__c requestRecord = [
            SELECT Employee__c, Leave_Type_Definition__c, Leave_Type_Code__c,
                   Leave_Type_Name__c, Status__c, Days__c, Reason__c
            FROM Leave_Request__c
            WHERE Id = :requestId
        ];

        Assert.areEqual(UserInfo.getUserId(), requestRecord.Employee__c);
        Assert.areEqual(annualDefinition.Id, requestRecord.Leave_Type_Definition__c);
        Assert.areEqual('ANNUAL', requestRecord.Leave_Type_Code__c);
        Assert.areEqual('Annual Leave Policy', requestRecord.Leave_Type_Name__c);
        Assert.areEqual('Draft', requestRecord.Status__c);
        Assert.areEqual(3, requestRecord.Days__c);
        Assert.areEqual('Family trip', requestRecord.Reason__c);
    }

    @IsTest
    static void testGetMyRequestsReturnsNewestDraftFirst() {
        Leave_Type_Definition__c annualDefinition = createLeaveTypeDefinition(
            'ANNUAL',
            'Annual Leave Policy'
        );

        Leave_Request__c firstRequest = new Leave_Request__c(
            Employee__c = UserInfo.getUserId(),
            Leave_Type_Definition__c = annualDefinition.Id,
            Start_Date__c = Date.today().addDays(2),
            End_Date__c = Date.today().addDays(2),
            Status__c = 'Draft',
            Balance_Deducted__c = false,
            Reason__c = 'First request'
        );
        insert firstRequest;
        Test.setCreatedDate(firstRequest.Id, DateTime.now().addMinutes(-10));

        Leave_Request__c secondRequest = new Leave_Request__c(
            Employee__c = UserInfo.getUserId(),
            Leave_Type_Definition__c = annualDefinition.Id,
            Start_Date__c = Date.today().addDays(5),
            End_Date__c = Date.today().addDays(6),
            Status__c = 'Draft',
            Balance_Deducted__c = false,
            Reason__c = 'Second request'
        );
        insert secondRequest;
        Test.setCreatedDate(secondRequest.Id, DateTime.now());

        Test.startTest();
        List<Leave_Request__c> myRequests = LeaveHomeController.getMyRequests();
        Test.stopTest();

        Assert.areEqual(2, myRequests.size());
        Assert.areEqual(secondRequest.Id, myRequests[0].Id);
        Assert.areEqual(firstRequest.Id, myRequests[1].Id);
        Assert.areEqual('Annual Leave Policy', myRequests[0].Leave_Type_Name__c);
    }

    @IsTest
    static void testSubmitLeaveActionReturnsReadableOverlapMessage() {
        Leave_Type_Definition__c annualDefinition = createLeaveTypeDefinition(
            'ANNUAL',
            'Annual Leave Policy'
        );
        insert new Leave_Balance__c(
            User__c = UserInfo.getUserId(),
            Year__c = Date.today().year(),
            Annual_Leave__c = 10,
            Sick_Leave__c = 5,
            Personal_Leave__c = 5
        );

        Leave_Request__c approvedRequest = new Leave_Request__c(
            Employee__c = UserInfo.getUserId(),
            Leave_Type_Definition__c = annualDefinition.Id,
            Start_Date__c = Date.today().addDays(3),
            End_Date__c = Date.today().addDays(4),
            Status__c = 'Approved',
            Balance_Deducted__c = true,
            Reason__c = 'Existing approved request'
        );
        insert approvedRequest;

        Leave_Request__c draftRequest = new Leave_Request__c(
            Employee__c = UserInfo.getUserId(),
            Leave_Type_Definition__c = annualDefinition.Id,
            Start_Date__c = Date.today().addDays(4),
            End_Date__c = Date.today().addDays(5),
            Status__c = 'Draft',
            Balance_Deducted__c = false,
            Reason__c = 'Overlapping draft'
        );
        insert draftRequest;

        Boolean blocked = false;
        try {
            LeaveHomeController.submitLeaveAction(draftRequest.Id);
            Assert.fail('Overlapping leave request should be blocked.');
        } catch (AuraHandledException ex) {
            blocked = true;
        }
        Assert.areEqual(true, blocked);

        Leave_Request__c refreshedDraft = [
            SELECT Status__c
            FROM Leave_Request__c
            WHERE Id = :draftRequest.Id
        ];
        Assert.areEqual('Draft', refreshedDraft.Status__c);
    }

    @IsTest
    static void testCreateLeaveRequestRejectsUnsupportedDefinition() {
        Leave_Type_Definition__c studyDefinition = new Leave_Type_Definition__c(
            Name = 'Study Leave Policy',
            Type_Code__c = 'STUDY',
            Is_Active__c = true,
            Policy_Version__c = 1
        );
        insert studyDefinition;

        Boolean blocked = false;
        try {
            LeaveHomeController.createLeaveRequest(
                studyDefinition.Id,
                Date.today().addDays(1),
                Date.today().addDays(1),
                'Training'
            );
            Assert.fail('Unsupported definition should be blocked.');
        } catch (AuraHandledException ex) {
            blocked = true;
        }
        Assert.areEqual(true, blocked);
        Assert.areEqual(0, [
            SELECT COUNT()
            FROM Leave_Request__c
            WHERE Leave_Type_Definition__c = :studyDefinition.Id
        ]);
    }

    private static User createUser(String key) {
        User currentUser = [
            SELECT ProfileId
            FROM User
            WHERE Id = :UserInfo.getUserId()
        ];
        String uniqueToken = key + String.valueOf(DateTime.now().getTime());
        User userRecord = new User(
            Alias = uniqueToken.substring(0, Math.min(8, uniqueToken.length())),
            Email = uniqueToken + '@example.com',
            EmailEncodingKey = 'UTF-8',
            LastName = 'Home',
            LanguageLocaleKey = 'en_US',
            LocaleSidKey = 'en_US',
            ProfileId = currentUser.ProfileId,
            TimeZoneSidKey = 'America/Los_Angeles',
            Username = uniqueToken + '@example.com'
        );
        insert userRecord;
        return userRecord;
    }

    private static Leave_Type_Definition__c createLeaveTypeDefinition(
        String typeCode,
        String name
    ) {
        Leave_Type_Definition__c definitionRecord = new Leave_Type_Definition__c(
            Name = name,
            Type_Code__c = typeCode,
            Is_Active__c = true,
            Allow_Carryover__c = typeCode == 'ANNUAL',
            Policy_Version__c = 1
        );
        insert definitionRecord;
        return definitionRecord;
    }
}
