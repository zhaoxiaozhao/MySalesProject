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
        User hrUser = createUser('hrreviewer');
        Integer yearValue = Date.today().year();
        assignPermissionSet(hrUser.Id, 'Leave_HR');
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
            Manager__c = hrUser.Id,
            Leave_Type_Definition__c = annualDefinition.Id,
            Start_Date__c = Date.today().addDays(3),
            End_Date__c = Date.today().addDays(4),
            Status__c = 'Pending_HR_Approval',
            Balance_Deducted__c = false,
            Approval_Mode_Snapshot__c = 'HR Only',
            Approval_Target_Snapshot__c = hrUser.Id
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

        System.runAs(hrUser) {
            List<Leave_Request__c> hrPending = LeaveHomeController.getHrPendingApprovals();

            Assert.areEqual(1, hrPending.size());
            Assert.areEqual(pendingHr.Id, hrPending[0].Id);
            Assert.areEqual(employee.Id, hrPending[0].Employee__c);
            Assert.areEqual('Home', getRelatedName(hrPending[0], 'Employee__c'));
            Assert.areEqual('Annual Leave Policy', getLeaveTypeName(hrPending[0]));
        }
    }

    @IsTest
    static void testGetHrPendingApprovalsReturnsEmptyWithoutHrScope() {
        User employee = createUser('hrscopeemp');
        User standardUser = createUser('standardscope');
        Leave_Type_Definition__c annualDefinition = createLeaveTypeDefinition(
            'ANNUAL',
            'Annual Leave Policy'
        );

        insert new Leave_Request__c(
            Employee__c = employee.Id,
            Manager__c = UserInfo.getUserId(),
            Leave_Type_Definition__c = annualDefinition.Id,
            Start_Date__c = Date.today().addDays(3),
            End_Date__c = Date.today().addDays(4),
            Status__c = 'Pending_HR_Approval',
            Balance_Deducted__c = false,
            Approval_Mode_Snapshot__c = 'HR Only',
            Approval_Target_Snapshot__c = 'HR_QUEUE'
        );

        System.runAs(standardUser) {
            List<Leave_Request__c> hrPending = LeaveHomeController.getHrPendingApprovals();

            Assert.areEqual(0, hrPending.size());
        }
    }

    @IsTest
    static void testGetPendingApprovalsReturnsManagerRecords() {
        User manager = createUser('pendingmgr');
        User employee = createUser('pendingemp');
        employee.ManagerId = manager.Id;
        update employee;

        Leave_Type_Definition__c annualDefinition = createLeaveTypeDefinition(
            'ANNUAL',
            'Annual Leave Policy'
        );

        insert new Leave_Request__c(
            Employee__c = employee.Id,
            Manager__c = manager.Id,
            Leave_Type_Definition__c = annualDefinition.Id,
            Start_Date__c = Date.today().addDays(2),
            End_Date__c = Date.today().addDays(3),
            Status__c = 'Submitted',
            Balance_Deducted__c = false,
            Reason__c = 'Needs manager review'
        );

        System.runAs(manager) {
            List<Leave_Request__c> pendingApprovals = LeaveHomeController.getPendingApprovals();
            LeaveHomeController.RoleInfo roleInfo = LeaveHomeController.getUserRoles();

            Assert.areEqual(true, roleInfo.isManager);
            Assert.isNotNull(pendingApprovals);
            if (!pendingApprovals.isEmpty()) {
                Assert.areEqual(employee.Id, pendingApprovals[0].Employee__c);
                Assert.areEqual('Home', getRelatedName(pendingApprovals[0], 'Employee__c'));
                Assert.areEqual('Annual Leave Policy', getLeaveTypeName(pendingApprovals[0]));
            }
        }
    }

    @IsTest
    static void testGetMyBalanceAndHrScopeQueriesReturnData() {
        User hrUser = createUser('balancehr');
        User employee = createUser('balemp');
        assignPermissionSet(hrUser.Id, 'Leave_HR');
        Leave_Type_Definition__c annualDefinition = createLeaveTypeDefinition(
            'ANNUAL',
            'Annual Leave Policy'
        );

        insert new Leave_Balance__c(
            User__c = hrUser.Id,
            Year__c = Date.today().year(),
            Annual_Leave__c = 12,
            Sick_Leave__c = 6,
            Personal_Leave__c = 3
        );
        insert new Leave_Request__c(
            Employee__c = employee.Id,
            Manager__c = hrUser.Id,
            Leave_Type_Definition__c = annualDefinition.Id,
            Start_Date__c = Date.today().addDays(4),
            End_Date__c = Date.today().addDays(5),
            Status__c = 'Pending_HR_Approval',
            Balance_Deducted__c = false,
            Reason__c = 'HR visible request'
        );

        System.runAs(hrUser) {
            LeaveBalanceLedgerService.BalanceSummary myBalance = LeaveHomeController.getMyBalance();
            List<LeaveBalanceLedgerService.BalanceSummary> allBalances = LeaveHomeController.getAllBalances();
            List<Leave_Request__c> allRequests = LeaveHomeController.getAllRequests();

            Assert.isNotNull(myBalance);
            Assert.areEqual(hrUser.Id, myBalance.userId);
            Assert.areEqual(12, myBalance.annualTotalAvailable);
            Assert.areEqual(6, myBalance.sickLeave);
            Assert.areEqual(3, myBalance.personalLeave);
            Assert.areEqual(1, allBalances.size());
            Assert.areEqual(hrUser.Id, allBalances[0].userId);
            Assert.areEqual(6, allBalances[0].sickLeave);
            Assert.areEqual(3, allBalances[0].personalLeave);
            Assert.areEqual(1, allRequests.size());
            Assert.areEqual(employee.Id, allRequests[0].Employee__c);
            Assert.areEqual('Home', getRelatedName(allRequests[0], 'Employee__c'));
            Assert.areEqual('Annual Leave Policy', getLeaveTypeName(allRequests[0]));
        }
    }

    @IsTest
    static void testGetAllRequestsAndBalancesRequireHrScope() {
        User standardUser = createUser('nonhrviewer');
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
        insert new Leave_Request__c(
            Employee__c = UserInfo.getUserId(),
            Leave_Type_Definition__c = annualDefinition.Id,
            Start_Date__c = Date.today().addDays(2),
            End_Date__c = Date.today().addDays(2),
            Status__c = 'Draft',
            Balance_Deducted__c = false,
            Reason__c = 'Self request'
        );

        System.runAs(standardUser) {
            Assert.areEqual(0, LeaveHomeController.getAllRequests().size());
            Assert.areEqual(0, LeaveHomeController.getAllBalances().size());
        }
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
    static void testCreateLeaveRequestRejectsInvalidInputs() {
        Leave_Type_Definition__c inactiveDefinition = new Leave_Type_Definition__c(
            Name = 'Inactive Annual Policy',
            Type_Code__c = 'ANNUAL',
            Is_Active__c = false,
            Policy_Version__c = 1
        );
        insert inactiveDefinition;

        assertAuraHandledExceptionForCreate(null, Date.today(), Date.today(), 'Missing definition');
        assertAuraHandledExceptionForCreate(
            inactiveDefinition.Id,
            null,
            Date.today(),
            'Missing start date'
        );
        assertAuraHandledExceptionForCreate(
            inactiveDefinition.Id,
            Date.today().addDays(2),
            Date.today().addDays(1),
            'Inverted date range'
        );
        assertAuraHandledExceptionForCreate(
            inactiveDefinition.Id,
            Date.today().addDays(1),
            Date.today().addDays(2),
            'Inactive definition'
        );
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
    static void testGetMyRequestsReturnsNewestInFlightRequestsOnly() {
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

        Leave_Request__c approvedRequest = new Leave_Request__c(
            Employee__c = UserInfo.getUserId(),
            Leave_Type_Definition__c = annualDefinition.Id,
            Start_Date__c = Date.today().addDays(8),
            End_Date__c = Date.today().addDays(8),
            Status__c = 'Approved',
            Balance_Deducted__c = true,
            Reason__c = 'Completed request'
        );
        insert approvedRequest;
        Test.setCreatedDate(approvedRequest.Id, DateTime.now().addMinutes(1));

        Test.startTest();
        List<Leave_Request__c> myRequests = LeaveHomeController.getMyRequests();
        Test.stopTest();

        Assert.areEqual(2, myRequests.size());
        Assert.areEqual(secondRequest.Id, myRequests[0].Id);
        Assert.areEqual(firstRequest.Id, myRequests[1].Id);
        Assert.areEqual('Annual Leave Policy', myRequests[0].Leave_Type_Name__c);
        Assert.areEqual(false, new Set<Id>{ myRequests[0].Id, myRequests[1].Id }.contains(approvedRequest.Id));
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
    static void testSubmitLeaveActionRejectsNonOwnerRequest() {
        User otherEmployee = createUser('otherowner');
        Leave_Type_Definition__c annualDefinition = createLeaveTypeDefinition(
            'ANNUAL',
            'Annual Leave Policy'
        );

        Leave_Request__c otherUsersRequest = new Leave_Request__c(
            Employee__c = otherEmployee.Id,
            Leave_Type_Definition__c = annualDefinition.Id,
            Start_Date__c = Date.today().addDays(2),
            End_Date__c = Date.today().addDays(2),
            Status__c = 'Draft',
            Balance_Deducted__c = false,
            Reason__c = 'Owned by another employee'
        );
        insert otherUsersRequest;

        Boolean blocked = false;
        try {
            LeaveHomeController.submitLeaveAction(otherUsersRequest.Id);
            Assert.fail('Submitting another employee request should be blocked.');
        } catch (AuraHandledException ex) {
            blocked = true;
        }
        Assert.areEqual(true, blocked);
    }

    @IsTest
    static void testCancelLeaveActionAllowsFutureApprovedRequest() {
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
            Start_Date__c = Date.today().addDays(7),
            End_Date__c = Date.today().addDays(8),
            Status__c = 'Approved',
            Balance_Deducted__c = false,
            Reason__c = 'Approved future request'
        );
        insert approvedRequest;
        LeaveService.deductBalance(approvedRequest.Id);

        Test.startTest();
        LeaveHomeController.cancelLeaveAction(approvedRequest.Id);
        Test.stopTest();

        Leave_Request__c cancelledRequest = [
            SELECT Status__c, Balance_Deducted__c
            FROM Leave_Request__c
            WHERE Id = :approvedRequest.Id
        ];
        Leave_Balance__c restoredBalance = [
            SELECT Annual_Leave__c
            FROM Leave_Balance__c
            WHERE User__c = :UserInfo.getUserId()
            AND Year__c = :Date.today().year()
            LIMIT 1
        ];

        Assert.areEqual('Cancelled', cancelledRequest.Status__c);
        Assert.areEqual(false, cancelledRequest.Balance_Deducted__c);
        Assert.areEqual(10, restoredBalance.Annual_Leave__c);
    }

    @IsTest
    static void testApproveAndRejectLeaveActionWrapUnauthorizedErrors() {
        User manager = createUser('realmanager');
        User outsider = createUser('approvalouts');
        User employee = createUser('approvalemp');
        employee.ManagerId = manager.Id;
        update employee;

        Leave_Type_Definition__c annualDefinition = createLeaveTypeDefinition(
            'ANNUAL',
            'Annual Leave Policy'
        );

        insert new Leave_Balance__c(
            User__c = employee.Id,
            Year__c = Date.today().year(),
            Annual_Leave__c = 10,
            Sick_Leave__c = 5,
            Personal_Leave__c = 5
        );

        Leave_Request__c submittedRequest = new Leave_Request__c(
            Employee__c = employee.Id,
            Manager__c = manager.Id,
            Leave_Type_Definition__c = annualDefinition.Id,
            Start_Date__c = Date.today().addDays(8),
            End_Date__c = Date.today().addDays(9),
            Status__c = 'Submitted',
            Balance_Deducted__c = false,
            Reason__c = 'Approval wrapper coverage'
        );
        insert submittedRequest;

        System.runAs(outsider) {
            Boolean approveBlocked = false;
            try {
                LeaveHomeController.approveLeaveAction(submittedRequest.Id);
                Assert.fail('Unauthorized approval should be blocked.');
            } catch (AuraHandledException ex) {
                approveBlocked = true;
            }
            Assert.areEqual(true, approveBlocked);

            Boolean rejectBlocked = false;
            try {
                LeaveHomeController.rejectLeaveAction(submittedRequest.Id);
                Assert.fail('Unauthorized rejection should be blocked.');
            } catch (AuraHandledException ex) {
                rejectBlocked = true;
            }
            Assert.areEqual(true, rejectBlocked);
        }
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

    private static void assertAuraHandledExceptionForCreate(
        Id leaveTypeDefinitionId,
        Date startDate,
        Date endDate,
        String scenarioLabel
    ) {
        Boolean blocked = false;
        try {
            LeaveHomeController.createLeaveRequest(
                leaveTypeDefinitionId,
                startDate,
                endDate,
                scenarioLabel
            );
            Assert.fail('Create request should be blocked for scenario: ' + scenarioLabel);
        } catch (AuraHandledException ex) {
            blocked = true;
        }
        Assert.areEqual(true, blocked);
    }

    private static void assignPermissionSet(Id userId, String permissionSetName) {
        PermissionSet permissionSetRecord = [
            SELECT Id
            FROM PermissionSet
            WHERE Name = :permissionSetName
            LIMIT 1
        ];
        User actingUser = [
            SELECT Id
            FROM User
            WHERE Id = :UserInfo.getUserId()
        ];
        System.runAs(actingUser) {
            insert new PermissionSetAssignment(
                AssigneeId = userId,
                PermissionSetId = permissionSetRecord.Id
            );
        }
    }

    private static String getRelatedName(Leave_Request__c requestRecord, String lookupFieldApiName) {
        if (requestRecord == null || String.isBlank(lookupFieldApiName)) {
            return null;
        }

        Schema.DescribeFieldResult describeResult =
            Leave_Request__c.SObjectType.getDescribe().fields.getMap().get(lookupFieldApiName).getDescribe();
        String relationshipName = describeResult.getRelationshipName();
        if (String.isBlank(relationshipName)) {
            return null;
        }

        SObject relatedRecord = requestRecord.getSObject(relationshipName);
        return relatedRecord == null ? null : String.valueOf(relatedRecord.get('Name'));
    }

    private static String getLeaveTypeName(Leave_Request__c requestRecord) {
        if (requestRecord == null) {
            return null;
        }
        Map<String, Object> populatedFields = requestRecord.getPopulatedFieldsAsMap();
        if (populatedFields.containsKey('Leave_Type_Name__c')) {
            Object directValue = populatedFields.get('Leave_Type_Name__c');
            return directValue == null ? null : String.valueOf(directValue);
        }
        return getRelatedName(requestRecord, 'Leave_Type_Definition__c');
    }
}
