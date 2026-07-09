public without sharing class LeaveSetupInitializationService {

    public static final Decimal DEFAULT_ANNUAL_DAYS = 15;
    public static final Decimal DEFAULT_SICK_DAYS = 10;
    public static final Decimal DEFAULT_PERSONAL_DAYS = 5;
    public static final String DEFAULT_HR_GROUP_KEY = 'HR_QUEUE';

    public class SetupSummary {
        public Integer leaveTypeInserted = 0;
        public Integer leaveTypeUpdated = 0;
        public Integer balanceInserted = 0;
        public Integer balanceUpdated = 0;
        public Integer processedUsers = 0;
    }

    private class LeaveTypeTemplate {
        String name;
        String typeCode;
        Boolean isActive;
        Boolean allowCarryover;
        Decimal carryoverLimit;
        Integer carryoverExpireMonth;
        Integer carryoverExpireDay;
        Boolean requiresHrApproval;
        String approvalMode;
        Decimal autoApproveBelowDays;
        Decimal escalateAboveDays;
        String escalationTarget;
        String approvalGroupKey;
        Decimal policyVersion;
    }

    public static SetupSummary initializeDefaultConfiguration(Integer yearValue) {
        return initializeDefaultConfiguration(
            yearValue,
            DEFAULT_ANNUAL_DAYS,
            DEFAULT_SICK_DAYS,
            DEFAULT_PERSONAL_DAYS,
            false
        );
    }

    public static SetupSummary initializeDefaultConfiguration(
        Integer yearValue,
        Decimal annualDays,
        Decimal sickDays,
        Decimal personalDays,
        Boolean overwriteExistingBalances
    ) {
        validateYear(yearValue);

        SetupSummary summary = initializeDefaultLeaveTypes();
        SetupSummary balanceSummary = initializeYearlyBalances(
            yearValue,
            annualDays,
            sickDays,
            personalDays,
            overwriteExistingBalances
        );
        summary.balanceInserted = balanceSummary.balanceInserted;
        summary.balanceUpdated = balanceSummary.balanceUpdated;
        summary.processedUsers = balanceSummary.processedUsers;
        return summary;
    }

    public static SetupSummary initializeDefaultLeaveTypes() {
        SetupSummary summary = new SetupSummary();
        List<LeaveTypeTemplate> templates = buildDefaultTemplates();
        Set<String> typeCodes = new Set<String>();
        for (LeaveTypeTemplate template : templates) {
            typeCodes.add(template.typeCode);
        }

        Map<String, Leave_Type_Definition__c> existingByTypeCode = new Map<String, Leave_Type_Definition__c>();
        for (Leave_Type_Definition__c existingDefinition : [
            SELECT Id, Type_Code__c
            FROM Leave_Type_Definition__c
            WHERE Type_Code__c IN :typeCodes
        ]) {
            if (!existingByTypeCode.containsKey(existingDefinition.Type_Code__c)) {
                existingByTypeCode.put(existingDefinition.Type_Code__c, existingDefinition);
            }
        }

        List<Leave_Type_Definition__c> definitionsToUpsert = new List<Leave_Type_Definition__c>();
        for (LeaveTypeTemplate template : templates) {
            Leave_Type_Definition__c definitionRecord = existingByTypeCode.containsKey(template.typeCode)
                ? existingByTypeCode.get(template.typeCode)
                : new Leave_Type_Definition__c();

            definitionRecord.Name = template.name;
            definitionRecord.Type_Code__c = template.typeCode;
            definitionRecord.Is_Active__c = template.isActive;
            definitionRecord.Allow_Carryover__c = template.allowCarryover;
            definitionRecord.Carryover_Limit__c = template.carryoverLimit;
            definitionRecord.Carryover_Expire_Month__c = template.carryoverExpireMonth;
            definitionRecord.Carryover_Expire_Day__c = template.carryoverExpireDay;
            definitionRecord.Requires_HR_Approval__c = template.requiresHrApproval;
            definitionRecord.Approval_Mode__c = template.approvalMode;
            definitionRecord.Auto_Approve_Below_Days__c = template.autoApproveBelowDays;
            definitionRecord.Escalate_Above_Days__c = template.escalateAboveDays;
            definitionRecord.Escalation_Target__c = template.escalationTarget;
            definitionRecord.Approval_Group_Key__c = template.approvalGroupKey;
            definitionRecord.Policy_Version__c = template.policyVersion;
            definitionsToUpsert.add(definitionRecord);

            if (existingByTypeCode.containsKey(template.typeCode)) {
                summary.leaveTypeUpdated++;
            } else {
                summary.leaveTypeInserted++;
            }
        }

        if (!definitionsToUpsert.isEmpty()) {
            upsert definitionsToUpsert;
        }
        return summary;
    }

    public static SetupSummary initializeYearlyBalances(
        Integer yearValue,
        Decimal annualDays,
        Decimal sickDays,
        Decimal personalDays,
        Boolean overwriteExistingBalances
    ) {
        return initializeYearlyBalancesForUsers(
            yearValue,
            annualDays,
            sickDays,
            personalDays,
            overwriteExistingBalances,
            null
        );
    }

    @TestVisible
    private static SetupSummary initializeYearlyBalancesForUsers(
        Integer yearValue,
        Decimal annualDays,
        Decimal sickDays,
        Decimal personalDays,
        Boolean overwriteExistingBalances,
        Set<Id> userIds
    ) {
        validateYear(yearValue);
        validateQuota(annualDays, 'Annual');
        validateQuota(sickDays, 'Sick');
        validateQuota(personalDays, 'Personal');

        List<User> targetUsers = queryTargetUsers(userIds);
        SetupSummary summary = new SetupSummary();
        summary.processedUsers = targetUsers.size();
        if (targetUsers.isEmpty()) {
            return summary;
        }

        Set<String> uniqueKeys = new Set<String>();
        for (User userRecord : targetUsers) {
            uniqueKeys.add(buildBalanceKey(userRecord.Id, yearValue));
        }

        Map<String, Leave_Balance__c> existingByKey = new Map<String, Leave_Balance__c>();
        for (Leave_Balance__c existingBalance : [
            SELECT Id, User__c, Year__c, Balance_Year__c, Status__c, Unique_Key__c,
                   Annual_Leave__c, Sick_Leave__c, Personal_Leave__c
            FROM Leave_Balance__c
            WHERE Unique_Key__c IN :uniqueKeys
        ]) {
            existingByKey.put(existingBalance.Unique_Key__c, existingBalance);
        }

        List<Leave_Balance__c> balancesToUpsert = new List<Leave_Balance__c>();
        Map<Id, Leave_Balance__c> balanceByUserId = new Map<Id, Leave_Balance__c>();
        for (User userRecord : targetUsers) {
            String uniqueKey = buildBalanceKey(userRecord.Id, yearValue);
            Leave_Balance__c balanceRecord = existingByKey.containsKey(uniqueKey)
                ? existingByKey.get(uniqueKey)
                : new Leave_Balance__c();

            balanceRecord.User__c = userRecord.Id;
            balanceRecord.Year__c = yearValue;
            balanceRecord.Balance_Year__c = yearValue;
            if (String.isBlank(balanceRecord.Status__c)) {
                balanceRecord.Status__c = 'Open';
            }
            balanceRecord.Unique_Key__c = uniqueKey;

            Boolean shouldPersist = !existingByKey.containsKey(uniqueKey);
            if (!existingByKey.containsKey(uniqueKey)) {
                balanceRecord.Annual_Leave__c = annualDays;
                balanceRecord.Sick_Leave__c = sickDays;
                balanceRecord.Personal_Leave__c = personalDays;
                summary.balanceInserted++;
            } else if (overwriteExistingBalances) {
                balanceRecord.Annual_Leave__c = annualDays;
                balanceRecord.Sick_Leave__c = sickDays;
                balanceRecord.Personal_Leave__c = personalDays;
                shouldPersist = true;
                summary.balanceUpdated++;
            } else {
                shouldPersist = applyMissingQuotaDefaults(
                    balanceRecord,
                    annualDays,
                    sickDays,
                    personalDays
                );
                if (shouldPersist) {
                    summary.balanceUpdated++;
                }
            }

            if (shouldPersist) {
                balancesToUpsert.add(balanceRecord);
            }
            balanceByUserId.put(userRecord.Id, balanceRecord);
        }

        if (!balancesToUpsert.isEmpty()) {
            upsert balancesToUpsert Leave_Balance__c.Fields.Unique_Key__c;
        }

        for (Leave_Balance__c persistedBalance : [
            SELECT Id, User__c, Year__c, Balance_Year__c, Status__c, Unique_Key__c,
                   Annual_Leave__c, Sick_Leave__c, Personal_Leave__c
            FROM Leave_Balance__c
            WHERE Unique_Key__c IN :uniqueKeys
        ]) {
            balanceByUserId.put(persistedBalance.User__c, persistedBalance);
        }

        Map<String, Decimal> quotaByTypeCode = new Map<String, Decimal>{
            'ANNUAL' => annualDays,
            'SICK' => sickDays,
            'PERSONAL' => personalDays
        };
        LeaveBalanceLedgerService.initializePolicyLines(
            balanceByUserId,
            yearValue,
            quotaByTypeCode,
            overwriteExistingBalances
        );
        return summary;
    }

    private static Boolean applyMissingQuotaDefaults(
        Leave_Balance__c balanceRecord,
        Decimal annualDays,
        Decimal sickDays,
        Decimal personalDays
    ) {
        Boolean changed = false;
        if (balanceRecord.Annual_Leave__c == null) {
            balanceRecord.Annual_Leave__c = annualDays;
            changed = true;
        }
        if (balanceRecord.Sick_Leave__c == null) {
            balanceRecord.Sick_Leave__c = sickDays;
            changed = true;
        }
        if (balanceRecord.Personal_Leave__c == null) {
            balanceRecord.Personal_Leave__c = personalDays;
            changed = true;
        }
        return changed;
    }

    private static List<User> queryTargetUsers(Set<Id> userIds) {
        if (userIds == null || userIds.isEmpty()) {
            return [
                SELECT Id
                FROM User
                WHERE IsActive = true
                AND UserType = 'Standard'
            ];
        }
        return [
            SELECT Id
            FROM User
            WHERE IsActive = true
            AND Id IN :userIds
        ];
    }

    private static void validateYear(Integer yearValue) {
        if (yearValue == null || yearValue < 2000 || yearValue > 2100) {
            throw new IllegalArgumentException('Year value is invalid for leave setup initialization');
        }
    }

    private static void validateQuota(Decimal quota, String label) {
        if (quota == null || quota < 0) {
            throw new IllegalArgumentException(label + ' quota must be zero or positive');
        }
    }

    private static String buildBalanceKey(Id userId, Integer yearValue) {
        return String.valueOf(userId) + '-' + String.valueOf(yearValue);
    }

    private static List<LeaveTypeTemplate> buildDefaultTemplates() {
        List<LeaveTypeTemplate> templates = new List<LeaveTypeTemplate>();
        templates.add(buildTemplate('Annual Leave', 'ANNUAL', true, true, 5, 3, 31, true, 'Manager Then HR', null, null, 'HR', DEFAULT_HR_GROUP_KEY, 1));
        templates.add(buildTemplate('Sick Leave', 'SICK', true, false, 0, null, null, false, 'Configurable', 1, 3, 'HR', DEFAULT_HR_GROUP_KEY, 1));
        templates.add(buildTemplate('Personal Leave', 'PERSONAL', true, false, 0, null, null, false, 'Manager Only', null, null, 'HR', null, 1));
        templates.add(buildTemplate('Compensatory Leave', 'COMP_OFF', true, false, 0, null, null, false, 'Manager Only', null, null, 'HR', null, 1));
        templates.add(buildTemplate('Marriage Leave', 'MARRIAGE', true, false, 0, null, null, true, 'Manager Then HR', null, null, 'HR', DEFAULT_HR_GROUP_KEY, 1));
        templates.add(buildTemplate('Maternity Leave', 'MATERNITY', true, false, 0, null, null, true, 'HR Only', null, null, 'HR', DEFAULT_HR_GROUP_KEY, 1));
        templates.add(buildTemplate('Paternity Leave', 'PATERNITY', true, false, 0, null, null, true, 'Manager Then HR', null, null, 'HR', DEFAULT_HR_GROUP_KEY, 1));
        templates.add(buildTemplate('Bereavement Leave', 'BEREAVEMENT', true, false, 0, null, null, true, 'HR Only', null, null, 'HR', DEFAULT_HR_GROUP_KEY, 1));
        templates.add(buildTemplate('Work Injury Leave', 'WORK_INJURY', true, false, 0, null, null, true, 'HR Only', null, null, 'HR', DEFAULT_HR_GROUP_KEY, 1));
        templates.add(buildTemplate('Study Leave', 'STUDY', true, false, 0, null, null, true, 'Manager Then HR', null, 5, 'Custom Queue', DEFAULT_HR_GROUP_KEY, 1));
        return templates;
    }

    private static LeaveTypeTemplate buildTemplate(
        String name,
        String typeCode,
        Boolean isActive,
        Boolean allowCarryover,
        Decimal carryoverLimit,
        Integer carryoverExpireMonth,
        Integer carryoverExpireDay,
        Boolean requiresHrApproval,
        String approvalMode,
        Decimal autoApproveBelowDays,
        Decimal escalateAboveDays,
        String escalationTarget,
        String approvalGroupKey,
        Decimal policyVersion
    ) {
        LeaveTypeTemplate template = new LeaveTypeTemplate();
        template.name = name;
        template.typeCode = typeCode;
        template.isActive = isActive;
        template.allowCarryover = allowCarryover;
        template.carryoverLimit = carryoverLimit;
        template.carryoverExpireMonth = carryoverExpireMonth;
        template.carryoverExpireDay = carryoverExpireDay;
        template.requiresHrApproval = requiresHrApproval;
        template.approvalMode = approvalMode;
        template.autoApproveBelowDays = autoApproveBelowDays;
        template.escalateAboveDays = escalateAboveDays;
        template.escalationTarget = escalationTarget;
        template.approvalGroupKey = approvalGroupKey;
        template.policyVersion = policyVersion;
        return template;
    }
}
