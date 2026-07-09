public without sharing class LeaveRequestHandler {

    public void beforeInsert(List<Leave_Request__c> records) {
        Map<Id, LeaveTypePolicyService.LeaveTypePolicy> policyByDefinitionId =
            getPoliciesByDefinitionId(records);
        for (Leave_Request__c req : records) {
            applyLeaveTypeSnapshot(req, policyByDefinitionId);
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
        Map<Id, LeaveTypePolicyService.LeaveTypePolicy> policyByDefinitionId =
            getPoliciesByDefinitionId(records);

        for (Leave_Request__c req : records) {
            Leave_Request__c old = oldMap.get(req.Id);
            if (req.Leave_Type_Definition__c != old.Leave_Type_Definition__c ||
                String.isBlank(req.Leave_Type_Code__c)) {
                applyLeaveTypeSnapshot(req, policyByDefinitionId);
            }

            if (req.Start_Date__c != null && req.End_Date__c != null
                    && (req.Start_Date__c != old.Start_Date__c || req.End_Date__c != old.End_Date__c)) {
                req.Days__c = req.Start_Date__c.daysBetween(req.End_Date__c) + 1;
            }
            if (req.Start_Date__c != old.Start_Date__c && req.Start_Date__c != null) {
                req.Balance_Year__c = req.Start_Date__c.year();
            }

            if (req.Employee__c != null && shouldResolveManager(req, old)) {
                employeeIds.add(req.Employee__c);
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

        for (Leave_Request__c req : records) {
            Leave_Request__c old = oldMap.get(req.Id);
            if (req.Employee__c != null && userMap.containsKey(req.Employee__c) && shouldResolveManager(req, old)) {
                req.Manager__c = userMap.get(req.Employee__c).ManagerId;
            }

            if (old.Status__c == 'Pending_Manager_Approval' && req.Status__c == 'Approved') {
                req.Status__c = LeaveApprovalRoutingService.resolveManagerApprovalStatus(req);
            }

            Boolean fromDraft = isDraftSubmission(old, req);
            if (!fromDraft) {
                continue;
            }

            req.Submitted_Time__c = System.now();

            if (LeaveService.hasOverlappingDates(req.Employee__c, req.Start_Date__c, req.End_Date__c, req.Id)) {
                req.addError('You already have an active leave request in this date range.');
                continue;
            }

            try {
                validateLeaveTypePolicy(req, policyByDefinitionId);
                LeaveBalanceLedgerService.validateBalance(
                    req.Employee__c,
                    req.Leave_Type_Definition__c,
                    req.Leave_Type_Code__c,
                    req.Start_Date__c,
                    req.End_Date__c,
                    req.Id
                );
                applyApprovalRouting(req, policyByDefinitionId);
            } catch (IllegalArgumentException e) {
                req.addError(e.getMessage());
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

        }

        if (!LeaveApprovalHistoryService.isTransitionHistorySuppressed()) {
            LeaveApprovalHistoryService.createTransitionHistories(records, oldMap);
        }

        for (Leave_Request__c req : records) {
            Leave_Request__c old = oldMap.get(req.Id);
            if (isDraftSubmission(old, req)) {
                LeaveBalanceLedgerService.reserveBalance(req.Id);
            }
            if (req.Status__c == 'Approved' && old.Status__c != 'Approved') {
                LeaveBalanceLedgerService.consumeReservedBalance(req.Id);
            } else if ((req.Status__c == 'Rejected' || req.Status__c == 'Cancelled')
                && req.Status__c != old.Status__c) {
                LeaveBalanceLedgerService.releaseReservedBalance(req.Id, null);
            }
        }

        if (!requestsToSyncSegments.isEmpty()) {
            LeaveRequestSegmentService.syncSegments(requestsToSyncSegments);
        }
    }

    private static void applyLeaveTypeSnapshot(
        Leave_Request__c req,
        Map<Id, LeaveTypePolicyService.LeaveTypePolicy> policyByDefinitionId
    ) {
        if (req.Leave_Type_Definition__c == null) {
            req.addError('Leave type definition is required.');
            return;
        }

        LeaveTypePolicyService.LeaveTypePolicy policy = policyByDefinitionId.get(req.Leave_Type_Definition__c);
        if (policy == null) {
            policy = LeaveTypePolicyService.getPolicyByDefinitionId(req.Leave_Type_Definition__c);
        }
        if (policy == null) {
            req.addError('Selected leave type definition does not exist.');
            return;
        }
        req.Leave_Type_Code__c = policy.typeCode;
        req.Leave_Type_Name__c = policy.typeName;
        req.Policy_Version__c = policy.policyVersion;
        req.Leave_Type_Definition__c = policy.definitionId;
    }

    private static void validateLeaveTypePolicy(
        Leave_Request__c req,
        Map<Id, LeaveTypePolicyService.LeaveTypePolicy> policyByDefinitionId
    ) {
        if (req.Leave_Type_Definition__c == null) {
            req.addError('Leave type definition is required.');
            return;
        }

        LeaveTypePolicyService.LeaveTypePolicy policy = policyByDefinitionId.get(req.Leave_Type_Definition__c);
        if (policy == null) {
            policy = LeaveTypePolicyService.getPolicyByDefinitionId(req.Leave_Type_Definition__c);
        }
        if (policy == null) {
            req.addError('Selected leave type definition does not exist.');
            return;
        }
        if (policy.isDefined && !policy.isActive) {
            req.addError('Selected leave type is inactive. Please choose another leave type.');
        }
    }

    private static void applyApprovalRouting(
        Leave_Request__c req,
        Map<Id, LeaveTypePolicyService.LeaveTypePolicy> policyByDefinitionId
    ) {
        LeaveTypePolicyService.LeaveTypePolicy policy = policyByDefinitionId.get(req.Leave_Type_Definition__c);
        if (policy == null) {
            policy = LeaveTypePolicyService.getPolicyByDefinitionId(req.Leave_Type_Definition__c);
        }

        LeaveApprovalRoutingService.RoutingDecision decision =
            LeaveApprovalRoutingService.resolveSubmissionDecision(req, policy, req.Manager__c);
        req.Status__c = decision.nextStatus;
        req.Approval_Mode_Snapshot__c = decision.approvalModeSnapshot;
        req.Approval_Target_Snapshot__c = decision.approvalTargetSnapshot;
    }

    private static Boolean shouldResolveManager(Leave_Request__c req, Leave_Request__c old) {
        return req.Status__c != 'Draft' || old.Status__c != 'Draft' || req.Employee__c != old.Employee__c;
    }

    private static Boolean isDraftSubmission(Leave_Request__c old, Leave_Request__c req) {
        return old.Status__c == 'Draft'
            && (req.Status__c == 'Submitted' || req.Status__c == 'Pending_Manager_Approval'
                || req.Status__c == 'Pending_HR_Approval' || req.Status__c == 'Approved');
    }

    private static Map<Id, LeaveTypePolicyService.LeaveTypePolicy> getPoliciesByDefinitionId(
        List<Leave_Request__c> records
    ) {
        Set<Id> definitionIds = new Set<Id>();
        for (Leave_Request__c req : records) {
            if (req.Leave_Type_Definition__c != null) {
                definitionIds.add(req.Leave_Type_Definition__c);
            }
        }
        return LeaveTypePolicyService.getPoliciesByDefinitionIds(definitionIds);
    }
}
