@IsTest
private class LeaveRequestSearchControllerTest {

    @IsTest
    static void testGetSearchContextReturnsManagerAndHrScopes() {
        User manager = createUser('searchcontext');
        User employee = createUser('searchworker');
        employee.ManagerId = manager.Id;
        update employee;
        assignPermissionSet(manager.Id, 'Leave_HR');

        System.runAs(manager) {
            LeaveRequestSearchController.SearchContext context =
                LeaveRequestSearchController.getSearchContext();
            Set<String> scopes = new Set<String>();
            for (LeaveRequestSearchController.OptionItem option : context.scopeOptions) {
                scopes.add(option.value);
            }

            Assert.areEqual(true, context.isManager);
            Assert.areEqual(true, context.isHR);
            Assert.areEqual(true, scopes.contains('MY'));
            Assert.areEqual(true, scopes.contains('TEAM'));
            Assert.areEqual(true, scopes.contains('HR_PENDING'));
            Assert.areEqual(true, scopes.contains('ALL'));
        }
    }

    @IsTest
    static void testSearchLeaveRequestsMyScopeReturnsOnlyCurrentUserRecords() {
        Leave_Type_Definition__c annualDefinition = createLeaveTypeDefinition('ANNUAL', 'Annual Leave Policy');
        User coworker = createUser('searchpeer');

        insert new Leave_Request__c(
            Employee__c = UserInfo.getUserId(),
            Leave_Type_Definition__c = annualDefinition.Id,
            Start_Date__c = Date.today().addDays(1),
            End_Date__c = Date.today().addDays(2),
            Status__c = 'Draft',
            Balance_Deducted__c = false,
            Reason__c = 'Family trip'
        );
        insert new Leave_Request__c(
            Employee__c = coworker.Id,
            Leave_Type_Definition__c = annualDefinition.Id,
            Start_Date__c = Date.today().addDays(3),
            End_Date__c = Date.today().addDays(4),
            Status__c = 'Approved',
            Balance_Deducted__c = true,
            Reason__c = 'Peer travel'
        );

        Test.startTest();
        List<LeaveRequestSearchController.LeaveRequestRow> rows =
            LeaveRequestSearchController.searchLeaveRequests(
                'Annual',
                null,
                null,
                'MY',
                null,
                null,
                50
            );
        Test.stopTest();

        Assert.areEqual(1, rows.size());
        Assert.areEqual('Family trip', rows[0].reason);
        Assert.areEqual(UserInfo.getUserId(), rows[0].employeeId);
    }

    @IsTest
    static void testSearchLeaveRequestsTeamScopeFiltersManagedEmployees() {
        User manager = createUser('searchmanager');
        User directReport = createUser('searchreport');
        User outsider = createUser('searchoutsider');
        directReport.ManagerId = manager.Id;
        update directReport;

        Leave_Type_Definition__c annualDefinition = createLeaveTypeDefinition('ANNUAL', 'Annual Leave Policy');

        insert new Leave_Request__c(
            Employee__c = directReport.Id,
            Manager__c = manager.Id,
            Leave_Type_Definition__c = annualDefinition.Id,
            Start_Date__c = Date.today().addDays(5),
            End_Date__c = Date.today().addDays(6),
            Status__c = 'Pending_Manager_Approval',
            Balance_Deducted__c = false,
            Reason__c = 'Managed request'
        );
        insert new Leave_Request__c(
            Employee__c = outsider.Id,
            Leave_Type_Definition__c = annualDefinition.Id,
            Start_Date__c = Date.today().addDays(7),
            End_Date__c = Date.today().addDays(7),
            Status__c = 'Draft',
            Balance_Deducted__c = false,
            Reason__c = 'Outside request'
        );

        System.runAs(manager) {
            List<LeaveRequestSearchController.LeaveRequestRow> rows =
                LeaveRequestSearchController.searchLeaveRequests(
                    null,
                    'Home',
                    'Pending_Manager_Approval',
                    'TEAM',
                    Date.today().addDays(4),
                    Date.today().addDays(8),
                    50
                );

            Assert.areEqual(1, rows.size());
            Assert.areEqual('Managed request', rows[0].reason);
            Assert.areEqual(directReport.Id, rows[0].employeeId);
        }
    }

    @IsTest
    static void testSearchLeaveRequestsHrPendingScopeRequiresHrPermission() {
        User hrUser = createUser('searchhr');
        assignPermissionSet(hrUser.Id, 'Leave_HR');
        User employee = createUser('searchhremp');
        Leave_Type_Definition__c annualDefinition = createLeaveTypeDefinition('ANNUAL', 'Annual Leave Policy');

        insert new Leave_Request__c(
            Employee__c = employee.Id,
            Leave_Type_Definition__c = annualDefinition.Id,
            Start_Date__c = Date.today().addDays(2),
            End_Date__c = Date.today().addDays(3),
            Status__c = 'Pending_HR_Approval',
            Balance_Deducted__c = false,
            Reason__c = 'HR queue request'
        );

        System.runAs(hrUser) {
            List<LeaveRequestSearchController.LeaveRequestRow> rows =
                LeaveRequestSearchController.searchLeaveRequests(
                    null,
                    null,
                    null,
                    'HR_PENDING',
                    null,
                    null,
                    50
                );

            Assert.areEqual(1, rows.size());
            Assert.areEqual('Pending_HR_Approval', rows[0].status);
        }
    }

    private static void assignPermissionSet(Id userId, String permissionSetName) {
        PermissionSet permissionSetRecord = [
            SELECT Id
            FROM PermissionSet
            WHERE Name = :permissionSetName
            LIMIT 1
        ];
        insert new PermissionSetAssignment(
            AssigneeId = userId,
            PermissionSetId = permissionSetRecord.Id
        );
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

    private static Leave_Type_Definition__c createLeaveTypeDefinition(String typeCode, String name) {
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
