public without sharing class LeaveTypePolicyService {

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

        List<Leave_Type_Definition__c> definitions = [
            SELECT Id, Name, Type_Code__c, Is_Active__c, Allow_Carryover__c, Carryover_Limit__c,
                   Carryover_Expire_Month__c, Carryover_Expire_Day__c, Requires_HR_Approval__c, Policy_Version__c
            FROM Leave_Type_Definition__c
            WHERE Type_Code__c IN :normalizedCodes
        ];

        for (Leave_Type_Definition__c definition : definitions) {
            LeaveTypePolicy policy = buildDefaultPolicy(definition.Type_Code__c);
            policy.definitionId = definition.Id;
            policy.typeCode = definition.Type_Code__c;
            policy.typeName = definition.Name;
            policy.isDefined = true;
            policy.isActive = definition.Is_Active__c;
            policy.allowCarryover = definition.Allow_Carryover__c;
            policy.carryoverLimit = definition.Carryover_Limit__c;
            policy.carryoverExpireMonth = toInteger(definition.Carryover_Expire_Month__c);
            policy.carryoverExpireDay = toInteger(definition.Carryover_Expire_Day__c);
            policy.requiresHrApproval = definition.Requires_HR_Approval__c;
            policy.policyVersion = definition.Policy_Version__c;
            policyByTypeCode.put(definition.Type_Code__c, policy);
        }

        return policyByTypeCode;
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
        policy.policyVersion = 1;
        return policy;
    }

    private static Integer toInteger(Decimal value) {
        return value == null ? null : Integer.valueOf(String.valueOf(value));
    }
}
