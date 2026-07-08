public without sharing class LeaveRequestHandler {

    public void beforeInsert(List<Leave_Request__c> records) {
        Map<String, LeaveTypePolicyService.LeaveTypePolicy> policyByTypeCode =
            getPolicyByTypeCode(records);
        for (Leave_Request__c req : records) {
            applyLeaveTypeSnapshot(req, policyByTypeCode);
            if (req.Employee__c == null) {
                req.Employee__c = UserInfo.getUserId();
            }
            if (req.Start_Date__c != null && req.End_Date__c != null) {
                req.Days__c = req.Start_Date__c.daysBetween(req.End_Date__c) + 1;
            }
            if (req.Start_Date__c != null) {
                req.Balance_Year__c = req.Start_Date__c.year();
            }
        }
    }

    public void beforeUpdate(List<Leave_Request__c> records, Map<Id, Leave_Request__c> oldMap) {
        Set<Id> employeeIds = new Set<Id>();
        Map<Id, User> userMap = new Map<Id, User>();
        Map<String, LeaveTypePolicyService.LeaveTypePolicy> policyByTypeCode =
            getPolicyByTypeCode(records);

        for (Leave_Request__c req : records) {
            Leave_Request__c old = oldMap.get(req.Id);
            if (req.Leave_Type__c != old.Leave_Type__c || req.Leave_Type_Definition__c == null) {
                applyLeaveTypeSnapshot(req, policyByTypeCode);
            }

            if (req.Start_Date__c != null && req.End_Date__c != null
                    && (req.Start_Date__c != old.Start_Date__c || req.End_Date__c != old.End_Date__c)) {
                req.Days__c = req.Start_Date__c.daysBetween(req.End_Date__c) + 1;
            }
            if (req.Start_Date__c != old.Start_Date__c && req.Start_Date__c != null) {
                req.Balance_Year__c = req.Start_Date__c.year();
            }

            Boolean fromDraft = old.Status__c == 'Draft'
                && (req.Status__c == 'Submitted' || req.Status__c == 'Pending_Manager_Approval'
                    || req.Status__c == 'Pending_HR_Approval');

            if (fromDraft) {
                if (req.Employee__c != null) {
                    employeeIds.add(req.Employee__c);
                }
                req.Submitted_Time__c = System.now();

                if (LeaveService.hasOverlappingDates(req.Employee__c, req.Start_Date__c, req.End_Date__c, req.Id)) {
                    req.addError('You already have an active leave request in this date range.');
                } else {
                    try {
                        validateLeaveTypePolicy(req, policyByTypeCode);
                        LeaveService.validateBalance(
                            req.Employee__c,
                            req.Leave_Type__c,
                            req.Days__c,
                            req.Start_Date__c,
                            req.End_Date__c,
                            req.Id
                        );
                    } catch (IllegalArgumentException e) {
                        req.addError(e.getMessage());
                    }
                }
            }
        }

        if (!employeeIds.isEmpty()) {
            for (User u : [SELECT Id, ManagerId FROM User WHERE Id IN :employeeIds]) {
                userMap.put(u.Id, u);
            }
            for (Leave_Request__c req : records) {
                if (req.Status__c != null && req.Status__c != 'Draft'
                        && req.Employee__c != null && userMap.containsKey(req.Employee__c)) {
                    req.Manager__c = userMap.get(req.Employee__c).ManagerId;
                }
            }
        }
    }

    public void afterInsert(List<Leave_Request__c> records) {
        LeaveRequestSegmentService.syncSegments(records);
    }

    public void afterUpdate(List<Leave_Request__c> records, Map<Id, Leave_Request__c> oldMap) {
        List<Leave_Request__c> requestsToSyncSegments = new List<Leave_Request__c>();
        for (Leave_Request__c req : records) {
            Leave_Request__c old = oldMap.get(req.Id);
            if (req.Start_Date__c != old.Start_Date__c ||
                req.End_Date__c != old.End_Date__c ||
                req.Leave_Type_Definition__c != old.Leave_Type_Definition__c ||
                req.Status__c != old.Status__c) {
                requestsToSyncSegments.add(req);
            }

            if (req.Status__c == 'Approved' && old.Status__c != 'Approved') {
                LeaveService.handleApprovalResult(req.Id, true);
            } else if (req.Status__c == 'Rejected' && old.Status__c != 'Rejected') {
                LeaveService.handleApprovalResult(req.Id, false);
            }
        }

        if (!requestsToSyncSegments.isEmpty()) {
            LeaveRequestSegmentService.syncSegments(requestsToSyncSegments);
        }
    }

    private static void applyLeaveTypeSnapshot(
        Leave_Request__c req,
        Map<String, LeaveTypePolicyService.LeaveTypePolicy> policyByTypeCode
    ) {
        String typeCode = LeaveTypePolicyService.normalizeLeaveTypeValue(req.Leave_Type__c);
        LeaveTypePolicyService.LeaveTypePolicy policy = policyByTypeCode.get(typeCode);
        if (policy == null) {
            policy = LeaveTypePolicyService.getPolicyByTypeCode(typeCode);
        }
        req.Leave_Type_Code__c = policy.typeCode;
        req.Leave_Type_Name__c = policy.isDefined && !String.isBlank(policy.typeName)
            ? policy.typeName
            : req.Leave_Type__c;
        req.Policy_Version__c = policy.policyVersion;
        req.Leave_Type_Definition__c = policy.definitionId;
    }

    private static void validateLeaveTypePolicy(
        Leave_Request__c req,
        Map<String, LeaveTypePolicyService.LeaveTypePolicy> policyByTypeCode
    ) {
        String typeCode = LeaveTypePolicyService.normalizeLeaveTypeValue(req.Leave_Type__c);
        LeaveTypePolicyService.LeaveTypePolicy policy = policyByTypeCode.get(typeCode);
        if (policy == null) {
            policy = LeaveTypePolicyService.getPolicyByTypeCode(typeCode);
        }
        if (policy.isDefined && !policy.isActive) {
            req.addError('Selected leave type is inactive. Please choose another leave type.');
        }
    }

    private static Map<String, LeaveTypePolicyService.LeaveTypePolicy> getPolicyByTypeCode(
        List<Leave_Request__c> records
    ) {
        Set<String> typeCodes = new Set<String>();
        for (Leave_Request__c req : records) {
            if (!String.isBlank(req.Leave_Type__c)) {
                typeCodes.add(LeaveTypePolicyService.normalizeLeaveTypeValue(req.Leave_Type__c));
            }
        }
        return LeaveTypePolicyService.getPoliciesByTypeCodes(typeCodes);
    }
}
