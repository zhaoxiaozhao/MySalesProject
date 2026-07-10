public without sharing class LeaveTypePolicyService {

    private static final List<String> POLICY_QUERY_FIELDS = new List<String>{
        'Id',
        'Name',
        'Type_Code__c',
        'Is_Active__c',
        'Allow_Carryover__c',
        'Carryover_Limit__c',
        'Carryover_Expire_Month__c',
        'Carryover_Expire_Day__c',
        'Requires_HR_Approval__c',
        'Approval_Mode__c',
        'Auto_Approve_Below_Days__c',
        'Escalate_Above_Days__c',
        'Escalation_Target__c',
        'Approval_Group_Key__c',
        'Policy_Version__c'
    };
    private static Set<String> nonQueryableDefinitionFields = new Set<String>();

    public class LeaveTypePolicy {
        public Id definitionId;
        public String typeCode;
        public String typeName;
        public Boolean isDefined;
        public Boolean isActive;
        public Boolean allowCarryover;
        public Decimal carryoverLimit;
        public Integer carryoverExpireMonth;
        public Integer carryoverExpireDay;
        public Boolean requiresHrApproval;
        public String approvalMode;
        public Decimal autoApproveBelowDays;
        public Decimal escalateAboveDays;
        public String escalationTarget;
        public String approvalGroupKey;
        public Decimal policyVersion;
    }

    public static LeaveTypePolicy getPolicyByLeaveTypeValue(String leaveTypeValue) {
        return getPolicyByTypeCode(normalizeLeaveTypeValue(leaveTypeValue));
    }

    public static LeaveTypePolicy getPolicyByTypeCode(String typeCode) {
        Map<String, LeaveTypePolicy> policyByTypeCode = getPoliciesByTypeCodes(new Set<String>{ typeCode });
        return policyByTypeCode.containsKey(typeCode)
            ? policyByTypeCode.get(typeCode)
            : buildDefaultPolicy(typeCode);
    }

    public static LeaveTypePolicy getPolicyByDefinitionId(Id definitionId) {
        Map<Id, LeaveTypePolicy> policyByDefinitionId = getPoliciesByDefinitionIds(
            new Set<Id>{ definitionId }
        );
        return policyByDefinitionId.get(definitionId);
    }

    public static Map<String, LeaveTypePolicy> getPoliciesByTypeCodes(Set<String> typeCodes) {
        Map<String, LeaveTypePolicy> policyByTypeCode = new Map<String, LeaveTypePolicy>();
        Set<String> normalizedCodes = new Set<String>();
        for (String typeCode : typeCodes) {
            if (String.isBlank(typeCode)) {
                continue;
            }
            normalizedCodes.add(typeCode);
            policyByTypeCode.put(typeCode, buildDefaultPolicy(typeCode));
        }

        if (normalizedCodes.isEmpty()) {
            return policyByTypeCode;
        }

        if (!hasDefinitionField('Type_Code__c')) {
            return policyByTypeCode;
        }

        for (SObject definitionRecord : queryDefinitionRecordsByTypeCodes(normalizedCodes)) {
            LeaveTypePolicy policy = buildPolicyFromDefinitionRecord(definitionRecord);
            if (!String.isBlank(policy.typeCode)) {
                policyByTypeCode.put(policy.typeCode, policy);
            }
        }

        return policyByTypeCode;
    }

    public static Map<Id, LeaveTypePolicy> getPoliciesByDefinitionIds(Set<Id> definitionIds) {
        Map<Id, LeaveTypePolicy> policyByDefinitionId = new Map<Id, LeaveTypePolicy>();
        Set<Id> filteredDefinitionIds = new Set<Id>();
        for (Id definitionId : definitionIds) {
            if (definitionId != null) {
                filteredDefinitionIds.add(definitionId);
            }
        }

        if (filteredDefinitionIds.isEmpty()) {
            return policyByDefinitionId;
        }

        for (SObject definitionRecord : queryDefinitionRecordsByIds(filteredDefinitionIds)) {
            Id definitionId = toIdValue(getDefinitionFieldValue(definitionRecord, 'Id'));
            if (definitionId != null) {
                policyByDefinitionId.put(definitionId, buildPolicyFromDefinitionRecord(definitionRecord));
            }
        }
        return policyByDefinitionId;
    }

    public static String normalizeLeaveTypeValue(String leaveTypeValue) {
        if (String.isBlank(leaveTypeValue)) {
            return null;
        }

        String normalizedValue = leaveTypeValue.trim().toUpperCase();
        normalizedValue = normalizedValue.replaceAll('[^A-Z0-9]+', '_');
        while (normalizedValue.contains('__')) {
            normalizedValue = normalizedValue.replace('__', '_');
        }
        if (normalizedValue.startsWith('_')) {
            normalizedValue = normalizedValue.substring(1);
        }
        if (normalizedValue.endsWith('_')) {
            normalizedValue = normalizedValue.substring(0, normalizedValue.length() - 1);
        }
        return normalizedValue;
    }

    private static LeaveTypePolicy buildDefaultPolicy(String typeCode) {
        LeaveTypePolicy policy = new LeaveTypePolicy();
        policy.typeCode = typeCode;
        policy.typeName = typeCode == null ? null : typeCode.replace('_', ' ');
        policy.isDefined = false;
        policy.isActive = true;
        policy.allowCarryover = 'ANNUAL' == typeCode;
        policy.carryoverLimit = 'ANNUAL' == typeCode ? LeaveAnnualCarryoverService.DEFAULT_CARRYOVER_LIMIT : 0;
        policy.carryoverExpireMonth = 'ANNUAL' == typeCode ? LeaveAnnualCarryoverService.DEFAULT_EXPIRY_MONTH : null;
        policy.carryoverExpireDay = 'ANNUAL' == typeCode ? LeaveAnnualCarryoverService.DEFAULT_EXPIRY_DAY : null;
        policy.requiresHrApproval = false;
        policy.approvalMode = resolveDefaultApprovalMode(false);
        policy.autoApproveBelowDays = null;
        policy.escalateAboveDays = null;
        policy.escalationTarget = 'HR';
        policy.approvalGroupKey = null;
        policy.policyVersion = 1;
        return policy;
    }

    private static LeaveTypePolicy buildPolicyFromDefinitionRecord(SObject definitionRecord) {
        String typeCode = toStringValue(getDefinitionFieldValue(definitionRecord, 'Type_Code__c'));
        LeaveTypePolicy policy = buildDefaultPolicy(typeCode);
        policy.definitionId = toIdValue(getDefinitionFieldValue(definitionRecord, 'Id'));
        policy.typeCode = typeCode;
        policy.typeName = toStringValue(getDefinitionFieldValue(definitionRecord, 'Name'));
        policy.isDefined = true;
        Boolean isActive = toBoolean(getDefinitionFieldValue(definitionRecord, 'Is_Active__c'));
        if (isActive != null) {
            policy.isActive = isActive;
        }

        Boolean allowCarryover = toBoolean(getDefinitionFieldValue(definitionRecord, 'Allow_Carryover__c'));
        if (allowCarryover != null) {
            policy.allowCarryover = allowCarryover;
        }

        Decimal carryoverLimit = toDecimal(getDefinitionFieldValue(definitionRecord, 'Carryover_Limit__c'));
        if (carryoverLimit != null) {
            policy.carryoverLimit = carryoverLimit;
        }

        Integer carryoverExpireMonth = toInteger(
            toDecimal(getDefinitionFieldValue(definitionRecord, 'Carryover_Expire_Month__c'))
        );
        if (carryoverExpireMonth != null) {
            policy.carryoverExpireMonth = carryoverExpireMonth;
        }

        Integer carryoverExpireDay = toInteger(
            toDecimal(getDefinitionFieldValue(definitionRecord, 'Carryover_Expire_Day__c'))
        );
        if (carryoverExpireDay != null) {
            policy.carryoverExpireDay = carryoverExpireDay;
        }

        Boolean requiresHrApproval = toBoolean(
            getDefinitionFieldValue(definitionRecord, 'Requires_HR_Approval__c')
        );
        if (requiresHrApproval != null) {
            policy.requiresHrApproval = requiresHrApproval;
        }

        String approvalMode = toStringValue(getDefinitionFieldValue(definitionRecord, 'Approval_Mode__c'));
        policy.approvalMode = String.isBlank(approvalMode)
            ? resolveDefaultApprovalMode(policy.requiresHrApproval)
            : approvalMode;

        Decimal autoApproveBelowDays = toDecimal(
            getDefinitionFieldValue(definitionRecord, 'Auto_Approve_Below_Days__c')
        );
        if (autoApproveBelowDays != null) {
            policy.autoApproveBelowDays = autoApproveBelowDays;
        }

        Decimal escalateAboveDays = toDecimal(
            getDefinitionFieldValue(definitionRecord, 'Escalate_Above_Days__c')
        );
        if (escalateAboveDays != null) {
            policy.escalateAboveDays = escalateAboveDays;
        }

        String escalationTarget = toStringValue(
            getDefinitionFieldValue(definitionRecord, 'Escalation_Target__c')
        );
        if (!String.isBlank(escalationTarget)) {
            policy.escalationTarget = escalationTarget;
        }

        String approvalGroupKey = toStringValue(
            getDefinitionFieldValue(definitionRecord, 'Approval_Group_Key__c')
        );
        if (!String.isBlank(approvalGroupKey)) {
            policy.approvalGroupKey = approvalGroupKey;
        }

        Decimal policyVersion = toDecimal(getDefinitionFieldValue(definitionRecord, 'Policy_Version__c'));
        if (policyVersion != null) {
            policy.policyVersion = policyVersion;
        }
        return policy;
    }

    private static List<SObject> queryDefinitionRecordsByTypeCodes(Set<String> typeCodes) {
        if (typeCodes == null || typeCodes.isEmpty()) {
            return new List<SObject>();
        }

        return queryDefinitionRecords(
            'Type_Code__c IN ' + buildSoqlStringInClause(typeCodes)
        );
    }

    private static List<SObject> queryDefinitionRecordsByIds(Set<Id> definitionIds) {
        if (definitionIds == null || definitionIds.isEmpty()) {
            return new List<SObject>();
        }

        return queryDefinitionRecords(
            'Id IN ' + buildSoqlIdInClause(definitionIds)
        );
    }

    private static List<SObject> queryDefinitionRecords(String whereClause) {
        while (true) {
            String soql = buildDefinitionSelectSoql();
            if (!String.isBlank(whereClause)) {
                soql += ' WHERE ' + whereClause;
            }
            try {
                return Database.query(soql);
            } catch (QueryException ex) {
                String missingFieldApiName = extractMissingFieldApiName(ex);
                if (String.isBlank(missingFieldApiName) ||
                    !POLICY_QUERY_FIELDS.contains(missingFieldApiName) ||
                    nonQueryableDefinitionFields.contains(missingFieldApiName)) {
                    throw ex;
                }
                nonQueryableDefinitionFields.add(missingFieldApiName);
            }
        }
        return new List<SObject>();
    }

    private static String buildDefinitionSelectSoql() {
        List<String> selectFields = new List<String>();
        for (String fieldApiName : POLICY_QUERY_FIELDS) {
            if (hasDefinitionField(fieldApiName) &&
                !nonQueryableDefinitionFields.contains(fieldApiName)) {
                selectFields.add(fieldApiName);
            }
        }
        if (selectFields.isEmpty()) {
            selectFields.add('Id');
        }
        return 'SELECT ' + String.join(selectFields, ', ') +
            ' FROM Leave_Type_Definition__c';
    }

    private static String extractMissingFieldApiName(QueryException ex) {
        String message = ex == null ? null : ex.getMessage();
        if (String.isBlank(message)) {
            return null;
        }

        String prefix = 'No such column \'';
        Integer prefixIndex = message.indexOf(prefix);
        if (prefixIndex < 0) {
            return null;
        }

        Integer fieldStartIndex = prefixIndex + prefix.length();
        Integer fieldEndIndex = message.indexOf('\'', fieldStartIndex);
        if (fieldEndIndex <= fieldStartIndex) {
            return null;
        }
        return message.substring(fieldStartIndex, fieldEndIndex);
    }

    private static String buildSoqlStringInClause(Set<String> values) {
        List<String> orderedValues = new List<String>();
        for (String value : values) {
            if (!String.isBlank(value)) {
                orderedValues.add('\'' + String.escapeSingleQuotes(value) + '\'');
            }
        }
        orderedValues.sort();
        return '(' + String.join(orderedValues, ', ') + ')';
    }

    private static String buildSoqlIdInClause(Set<Id> ids) {
        List<String> orderedIds = new List<String>();
        for (Id recordId : ids) {
            if (recordId != null) {
                orderedIds.add('\'' + String.escapeSingleQuotes(String.valueOf(recordId)) + '\'');
            }
        }
        orderedIds.sort();
        return '(' + String.join(orderedIds, ', ') + ')';
    }

    private static Boolean hasDefinitionField(String fieldApiName) {
        return !String.isBlank(fieldApiName) &&
            Leave_Type_Definition__c.SObjectType.getDescribe().fields.getMap().containsKey(fieldApiName);
    }

    private static Object getDefinitionFieldValue(SObject definitionRecord, String fieldApiName) {
        if (definitionRecord == null || !hasDefinitionField(fieldApiName)) {
            return null;
        }

        Map<String, Object> populatedFields = definitionRecord.getPopulatedFieldsAsMap();
        return populatedFields.containsKey(fieldApiName)
            ? populatedFields.get(fieldApiName)
            : null;
    }

    private static String resolveDefaultApprovalMode(Boolean requiresHrApproval) {
        return requiresHrApproval ? 'Manager Then HR' : 'Manager Only';
    }

    private static String toStringValue(Object value) {
        return value == null ? null : String.valueOf(value);
    }

    private static Boolean toBoolean(Object value) {
        return value == null ? null : (Boolean)value;
    }

    private static Decimal toDecimal(Object value) {
        return value == null ? null : (Decimal)value;
    }

    private static Id toIdValue(Object value) {
        return value == null ? null : (Id)value;
    }

    private static Integer toInteger(Decimal value) {
        return value == null ? null : Integer.valueOf(String.valueOf(value));
    }
}
