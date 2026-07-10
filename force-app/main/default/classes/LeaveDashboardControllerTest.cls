@IsTest
private class LeaveDashboardControllerTest {

    @IsTest
    static void testGetCalendarReturnsMyRequestsForEmployeeScope() {
        User employee = createUser('dashself');
        User otherUser = createUser('dashother');
        assignPermissionSet(employee.Id, 'Leave_Employee');
        Leave_Type_Definition__c definitionRecord = createLeaveTypeDefinition(
            'ANNUAL',
            'Annual Leave Policy'
        );

        insert new List<Leave_Request__c>{
            new Leave_Request__c(
                OwnerId = employee.Id,
                Employee__c = employee.Id,
                Leave_Type_Definition__c = definitionRecord.Id,
                Start_Date__c = Date.today().toStartOfMonth().addDays(2),
                End_Date__c = Date.today().toStartOfMonth().addDays(3),
                Status__c = 'Approved',
                Balance_Deducted__c = true,
                Reason__c = 'Self request'
            ),
            new Leave_Request__c(
                OwnerId = otherUser.Id,
                Employee__c = otherUser.Id,
                Leave_Type_Definition__c = definitionRecord.Id,
                Start_Date__c = Date.today().toStartOfMonth().addDays(4),
                End_Date__c = Date.today().toStartOfMonth().addDays(5),
                Status__c = 'Approved',
                Balance_Deducted__c = true,
                Reason__c = 'Other request'
            )
        };

        System.runAs(employee) {
            LeaveDashboardController.CalendarPayload payload =
                LeaveDashboardController.getCalendar(Date.today());

            Assert.areEqual('MY', payload.scopeLabel);
            Assert.areEqual(1, payload.entries.size());
            Assert.areEqual(employee.Id, payload.entries[0].employeeId);
        }
    }

    @IsTest
    static void testGetCalendarReturnsDirectReportRequestsForManagerScope() {
        User manager = createUser('dashmgr');
        User employee = createUser('dashemployee');
        User unrelatedUser = createUser('dashunrel');
        assignPermissionSet(manager.Id, 'Leave_Manager');
        employee.ManagerId = manager.Id;
        update employee;

        Leave_Type_Definition__c definitionRecord = createLeaveTypeDefinition(
            'ANNUAL',
            'Annual Leave Policy'
        );

        insert new List<Leave_Request__c>{
            new Leave_Request__c(
                Employee__c = employee.Id,
                Manager__c = manager.Id,
                Leave_Type_Definition__c = definitionRecord.Id,
                Start_Date__c = Date.today().toStartOfMonth().addDays(7),
                End_Date__c = Date.today().toStartOfMonth().addDays(8),
                Status__c = 'Submitted',
                Balance_Deducted__c = false,
                Reason__c = 'Direct report request'
            ),
            new Leave_Request__c(
                Employee__c = unrelatedUser.Id,
                Leave_Type_Definition__c = definitionRecord.Id,
                Start_Date__c = Date.today().toStartOfMonth().addDays(9),
                End_Date__c = Date.today().toStartOfMonth().addDays(10),
                Status__c = 'Approved',
                Balance_Deducted__c = true,
                Reason__c = 'Hidden request'
            )
        };

        System.runAs(manager) {
            LeaveDashboardController.CalendarPayload payload =
                LeaveDashboardController.getCalendar(Date.today());

            Assert.areEqual('TEAM', payload.scopeLabel);
            Assert.areEqual(1, payload.entries.size());
            Assert.areEqual(employee.Id, payload.entries[0].employeeId);
        }
    }

    @IsTest
    static void testGetCalendarReturnsAllRequestsForHrScope() {
        User hrUser = createUser('dashhr');
        User employeeOne = createUser('dashhrone');
        User employeeTwo = createUser('dashhrtwo');
        assignPermissionSet(hrUser.Id, 'Leave_HR');

        Leave_Type_Definition__c definitionRecord = createLeaveTypeDefinition(
            'ANNUAL',
            'Annual Leave Policy'
        );

        insert new List<Leave_Request__c>{
            new Leave_Request__c(
                Employee__c = employeeOne.Id,
                Leave_Type_Definition__c = definitionRecord.Id,
                Start_Date__c = Date.today().toStartOfMonth().addDays(11),
                End_Date__c = Date.today().toStartOfMonth().addDays(12),
                Status__c = 'Pending_HR_Approval',
                Balance_Deducted__c = false,
                Reason__c = 'HR review request one'
            ),
            new Leave_Request__c(
                Employee__c = employeeTwo.Id,
                Leave_Type_Definition__c = definitionRecord.Id,
                Start_Date__c = Date.today().toStartOfMonth().addDays(13),
                End_Date__c = Date.today().toStartOfMonth().addDays(14),
                Status__c = 'Approved',
                Balance_Deducted__c = true,
                Reason__c = 'HR review request two'
            )
        };

        System.runAs(hrUser) {
            LeaveDashboardController.CalendarPayload payload =
                LeaveDashboardController.getCalendar(Date.today());

            Assert.areEqual('ALL', payload.scopeLabel);
            Assert.areEqual(2, payload.entries.size());
        }
    }

    private static Leave_Type_Definition__c createLeaveTypeDefinition(
        String typeCode,
        String name
    ) {
        Leave_Type_Definition__c definitionRecord = new Leave_Type_Definition__c(
            Name = name,
            Type_Code__c = typeCode,
            Is_Active__c = true,
            Policy_Version__c = 1
        );
        insert definitionRecord;
        return definitionRecord;
    }

    private static User createUser(String aliasPrefix) {
        Profile standardProfile = [
            SELECT Id
            FROM Profile
            WHERE Name = 'Standard User'
            LIMIT 1
        ];

        String uniqueValue = aliasPrefix + String.valueOf(Math.mod(Crypto.getRandomInteger(), 1000000)).replace('-', '7');
        User userRecord = new User(
            Alias = aliasPrefix.length() > 8 ? aliasPrefix.substring(0, 8) : aliasPrefix,
            Email = uniqueValue + '@example.com',
            EmailEncodingKey = 'UTF-8',
            LastName = aliasPrefix,
            LanguageLocaleKey = 'en_US',
            LocaleSidKey = 'en_US',
            ProfileId = standardProfile.Id,
            TimeZoneSidKey = 'America/Los_Angeles',
            UserName = uniqueValue + '@example.com'
        );
        insert userRecord;
        return userRecord;
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
}
