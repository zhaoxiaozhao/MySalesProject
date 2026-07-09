@IsTest
private class LeaveSetupInitializationServiceTest {

    @IsTest
    static void testInitializeDefaultLeaveTypesCreatesRichTemplates() {
        Test.startTest();
        LeaveSetupInitializationService.SetupSummary summary =
            LeaveSetupInitializationService.initializeDefaultLeaveTypes();
        Test.stopTest();

        Map<String, Leave_Type_Definition__c> definitionsByTypeCode =
            new Map<String, Leave_Type_Definition__c>();
        for (Leave_Type_Definition__c definitionRecord : [
            SELECT Name, Type_Code__c, Is_Active__c, Allow_Carryover__c,
                   Carryover_Limit__c, Carryover_Expire_Month__c, Carryover_Expire_Day__c,
                   Requires_HR_Approval__c, Approval_Mode__c, Auto_Approve_Below_Days__c,
                   Escalate_Above_Days__c, Escalation_Target__c, Approval_Group_Key__c
            FROM Leave_Type_Definition__c
            WHERE Type_Code__c IN ('ANNUAL', 'SICK', 'PERSONAL', 'COMP_OFF', 'MARRIAGE',
                'MATERNITY', 'PATERNITY', 'BEREAVEMENT', 'WORK_INJURY', 'STUDY')
        ]) {
            definitionsByTypeCode.put(definitionRecord.Type_Code__c, definitionRecord);
        }

        Assert.areEqual(10, definitionsByTypeCode.size());
        Assert.areEqual(10, summary.leaveTypeInserted);

        Leave_Type_Definition__c annualDefinition = definitionsByTypeCode.get('ANNUAL');
        Assert.areEqual('Annual Leave', annualDefinition.Name);
        Assert.areEqual(true, annualDefinition.Allow_Carryover__c);
        Assert.areEqual(5, annualDefinition.Carryover_Limit__c);
        Assert.areEqual(3, Integer.valueOf(String.valueOf(annualDefinition.Carryover_Expire_Month__c)));
        Assert.areEqual(31, Integer.valueOf(String.valueOf(annualDefinition.Carryover_Expire_Day__c)));
        Assert.areEqual('Manager Then HR', annualDefinition.Approval_Mode__c);

        Leave_Type_Definition__c sickDefinition = definitionsByTypeCode.get('SICK');
        Assert.areEqual('Configurable', sickDefinition.Approval_Mode__c);
        Assert.areEqual(1, sickDefinition.Auto_Approve_Below_Days__c);
        Assert.areEqual(3, sickDefinition.Escalate_Above_Days__c);

        Leave_Type_Definition__c maternityDefinition = definitionsByTypeCode.get('MATERNITY');
        Assert.areEqual('HR Only', maternityDefinition.Approval_Mode__c);
        Assert.areEqual(true, maternityDefinition.Requires_HR_Approval__c);
        Assert.areEqual('HR_QUEUE', maternityDefinition.Approval_Group_Key__c);
    }

    @IsTest
    static void testInitializeYearlyBalancesCreatesMissingRecordsAndPreservesExistingValues() {
        Integer yearValue = Date.today().year();
        User userOne = createEmployeeUser('initbalone');
        User userTwo = createEmployeeUser('initbaltwo');

        insert new Leave_Balance__c(
            User__c = userOne.Id,
            Year__c = yearValue,
            Annual_Leave__c = 22,
            Sick_Leave__c = 11,
            Personal_Leave__c = 7
        );

        Test.startTest();
        LeaveSetupInitializationService.SetupSummary summary =
            LeaveSetupInitializationService.initializeYearlyBalancesForUsers(
                yearValue,
                15,
                10,
                5,
                false,
                new Set<Id>{ userOne.Id, userTwo.Id }
            );
        Test.stopTest();

        Map<Id, Leave_Balance__c> balancesByUser = new Map<Id, Leave_Balance__c>();
        for (Leave_Balance__c balanceRecord : [
            SELECT User__c, Annual_Leave__c, Sick_Leave__c, Personal_Leave__c, Unique_Key__c
            FROM Leave_Balance__c
            WHERE Year__c = :yearValue
            AND User__c IN :new Set<Id>{ userOne.Id, userTwo.Id }
        ]) {
            balancesByUser.put(balanceRecord.User__c, balanceRecord);
        }

        Assert.areEqual(2, balancesByUser.size());
        Assert.areEqual(2, summary.processedUsers);
        Assert.areEqual(1, summary.balanceInserted);
        Assert.areEqual(0, summary.balanceUpdated);
        Assert.areEqual(22, balancesByUser.get(userOne.Id).Annual_Leave__c);
        Assert.areEqual(11, balancesByUser.get(userOne.Id).Sick_Leave__c);
        Assert.areEqual(7, balancesByUser.get(userOne.Id).Personal_Leave__c);
        Assert.areEqual(15, balancesByUser.get(userTwo.Id).Annual_Leave__c);
        Assert.areEqual(10, balancesByUser.get(userTwo.Id).Sick_Leave__c);
        Assert.areEqual(5, balancesByUser.get(userTwo.Id).Personal_Leave__c);
        Assert.areEqual(
            userTwo.Id + '-' + String.valueOf(yearValue),
            balancesByUser.get(userTwo.Id).Unique_Key__c
        );
    }

    @IsTest
    static void testInitializeDefaultConfigurationOverwritesWhenRequested() {
        Integer yearValue = Date.today().year();
        User userRecord = createEmployeeUser('initoverwrite');

        insert new Leave_Type_Definition__c(
            Name = 'Old Annual Policy',
            Type_Code__c = 'ANNUAL',
            Is_Active__c = false,
            Allow_Carryover__c = false,
            Approval_Mode__c = 'Manager Only',
            Policy_Version__c = 9
        );
        insert new Leave_Balance__c(
            User__c = userRecord.Id,
            Year__c = yearValue,
            Annual_Leave__c = 8,
            Sick_Leave__c = 3,
            Personal_Leave__c = 2
        );

        Test.startTest();
        LeaveSetupInitializationService.SetupSummary summary =
            LeaveSetupInitializationService.initializeDefaultConfiguration(
                yearValue,
                18,
                12,
                6,
                true
            );
        Test.stopTest();

        Leave_Type_Definition__c annualDefinition = [
            SELECT Name, Is_Active__c, Allow_Carryover__c, Approval_Mode__c
            FROM Leave_Type_Definition__c
            WHERE Type_Code__c = 'ANNUAL'
            LIMIT 1
        ];
        Leave_Balance__c balanceRecord = [
            SELECT Annual_Leave__c, Sick_Leave__c, Personal_Leave__c
            FROM Leave_Balance__c
            WHERE User__c = :userRecord.Id
            AND Year__c = :yearValue
            LIMIT 1
        ];

        Assert.areEqual(true, summary.leaveTypeUpdated > 0);
        Assert.areEqual(1, summary.balanceUpdated);
        Assert.areEqual('Annual Leave', annualDefinition.Name);
        Assert.areEqual(true, annualDefinition.Is_Active__c);
        Assert.areEqual(true, annualDefinition.Allow_Carryover__c);
        Assert.areEqual('Manager Then HR', annualDefinition.Approval_Mode__c);
        Assert.areEqual(18, balanceRecord.Annual_Leave__c);
        Assert.areEqual(12, balanceRecord.Sick_Leave__c);
        Assert.areEqual(6, balanceRecord.Personal_Leave__c);
    }

    @IsTest
    static void testInitializationJobRunsDefaultSetup() {
        Integer yearValue = Date.today().year();
        User userRecord = createEmployeeUser('initjob');

        Test.startTest();
        System.enqueueJob(new LeaveSetupInitializationJob(yearValue, 16, 9, 4, false));
        Test.stopTest();

        Leave_Balance__c balanceRecord = [
            SELECT Annual_Leave__c, Sick_Leave__c, Personal_Leave__c
            FROM Leave_Balance__c
            WHERE User__c = :userRecord.Id
            AND Year__c = :yearValue
            LIMIT 1
        ];
        Integer definitionCount = [
            SELECT COUNT()
            FROM Leave_Type_Definition__c
            WHERE Type_Code__c IN ('ANNUAL', 'SICK', 'PERSONAL', 'COMP_OFF')
        ];

        Assert.areEqual(16, balanceRecord.Annual_Leave__c);
        Assert.areEqual(9, balanceRecord.Sick_Leave__c);
        Assert.areEqual(4, balanceRecord.Personal_Leave__c);
        Assert.areEqual(4, definitionCount);
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
            LastName = 'Setup',
            LanguageLocaleKey = 'en_US',
            LocaleSidKey = 'en_US',
            ProfileId = currentUser.ProfileId,
            TimeZoneSidKey = 'America/Los_Angeles',
            Username = uniqueToken + '@example.com'
        );
        insert employee;
        return employee;
    }
}
