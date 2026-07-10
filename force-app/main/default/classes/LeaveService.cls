public without sharing class LeaveService {

    private static final String LEAVE_HR_PERMISSION_SET = 'Leave_HR';
    private static final String LEAVE_ADMIN_PERMISSION_SET = 'Leave_Admin';
    private static final String MANAGER_APPROVAL_PROCESS_NAME = 'Leave_Request_Approval';

    public static void submitLeave(Id leaveRequestId) {
        Savepoint savepointToken = Database.setSavepoint();
        Leave_Request__c req = [
            SELECT Id, Employee__c, Manager__c, Start_Date__c, End_Date__c,
                   Days__c, Leave_Type_Code__c, Status__c, Approval_Mode_Snapshot__c,
                   Approval_Target_Snapshot__c
            FROM Leave_Request__c
            WHERE Id = :leaveRequestId
        ];

        User emp = [SELECT Id, ManagerId FROM User WHERE Id = :req.Employee__c];

        req.Manager__c = emp.ManagerId;
        req.Status__c = 'Submitted';
        req.Submitted_Time__c = System.now();
        try {
            update req;
            Leave_Request__c submittedRequest = [
                SELECT Id, Status__c
                FROM Leave_Request__c
                WHERE Id = :req.Id
            ];

            if (submittedRequest.Status__c == 'Submitted') {
                Approval.ProcessSubmitRequest submitReq = new Approval.ProcessSubmitRequest();
                submitReq.setObjectId(req.Id);
                submitReq.setSubmitterId(UserInfo.getUserId());
                submitReq.setProcessDefinitionNameOrId(MANAGER_APPROVAL_PROCESS_NAME);
                submitReq.setSkipEntryCriteria(true);
                Approval.process(submitReq);
            }
        } catch (Exception ex) {
            Database.rollback(savepointToken);
            throw ex;
        }
    }

    public static void approveLeave(Id leaveRequestId, Id approverId, String comments) {
        Leave_Request__c req = loadApprovalRequest(leaveRequestId);

        String nextStatus;
        String stage;
        if (req.Status__c == 'Submitted') {
            validateApproverAuthorization(req, approverId);
            LeaveApprovalHistoryService.suppressTransitionHistory(true);
            try {
                processPendingManagerApproval(req.Id, 'Approve', comments);
            } finally {
                LeaveApprovalHistoryService.suppressTransitionHistory(false);
            }
            insertManagerApprovalHistory(req.Id, approverId, 'Approved', comments);
            return;
        }

        if (req.Status__c == 'Pending_Manager_Approval') {
            nextStatus = 'Approved';
            stage = 'Manager_Approval';
        } else if (req.Status__c == 'Pending_HR_Approval') {
            nextStatus = 'Approved';
            stage = 'HR_Approval';
        } else {
            throw new IllegalArgumentException('Leave request is not in an approvable status');
        }

        validateApproverAuthorization(req, approverId);
        applyApprovalSnapshots(req);

        req.Status__c = nextStatus;
        LeaveApprovalHistoryService.suppressTransitionHistory(true);
        try {
            update req;
        } finally {
            LeaveApprovalHistoryService.suppressTransitionHistory(false);
        }

        Leave_Approval_History__c history = LeaveApprovalHistoryService.buildHistory(req, stage, 'Approved', comments);
        history.Approver__c = approverId;
        insert history;
    }

    public static void rejectLeave(Id leaveRequestId, Id approverId, String comments) {
        Leave_Request__c req = loadApprovalRequest(leaveRequestId);

        if (req.Status__c == 'Submitted') {
            validateApproverAuthorization(req, approverId);
            LeaveApprovalHistoryService.suppressTransitionHistory(true);
            try {
                processPendingManagerApproval(req.Id, 'Reject', comments);
            } finally {
                LeaveApprovalHistoryService.suppressTransitionHistory(false);
            }
            insertManagerApprovalHistory(req.Id, approverId, 'Rejected', comments);
            return;
        }

        if (req.Status__c != 'Pending_Manager_Approval' && req.Status__c != 'Pending_HR_Approval') {
            throw new IllegalArgumentException('Leave request is not in a rejectable status');
        }

        validateApproverAuthorization(req, approverId);
        applyApprovalSnapshots(req);

        String stage = req.Status__c == 'Pending_HR_Approval' ? 'HR_Approval' : 'Manager_Approval';
        req.Status__c = 'Rejected';
        LeaveApprovalHistoryService.suppressTransitionHistory(true);
        try {
            update req;
        } finally {
            LeaveApprovalHistoryService.suppressTransitionHistory(false);
        }

        Leave_Approval_History__c history = LeaveApprovalHistoryService.buildHistory(req, stage, 'Rejected', comments);
        history.Approver__c = approverId;
        insert history;
    }

    public static void cancelLeave(Id leaveRequestId, Id actorId, String comments) {
        Leave_Request__c req = [
            SELECT Id, Employee__c, Status__c, Balance_Deducted__c, Start_Date__c, End_Date__c,
                   Approval_Mode_Snapshot__c, Approval_Target_Snapshot__c
            FROM Leave_Request__c
            WHERE Id = :leaveRequestId
        ];

        if (req.Status__c == 'Approved'
            && (req.Start_Date__c == null || req.Start_Date__c <= System.today())) {
            throw new IllegalArgumentException(
                'Approved leave can only be cancelled before the leave start date.'
            );
        }
        if (!canCancel(req)) {
            throw new IllegalArgumentException('Leave request is not in a cancellable status');
        }

        recallPendingApprovalIfNeeded(req.Id, comments);

        req.Status__c = 'Cancelled';
        LeaveApprovalHistoryService.suppressTransitionHistory(true);
        try {
            update req;
        } finally {
            LeaveApprovalHistoryService.suppressTransitionHistory(false);
        }

        Leave_Approval_History__c history = LeaveApprovalHistoryService.buildHistory(
            req,
            'Cancellation',
            'Cancelled',
            comments
        );
        history.Approver__c = actorId;
        insert history;
    }

    public static void deductBalance(Id leaveRequestId) {
        LeaveBalanceLedgerService.consumeReservedBalance(leaveRequestId);
    }

    public static Boolean hasOverlappingDates(Id employeeId, Date startDate, Date endDate, Id excludeRequestId) {
        List<Leave_Request__c> overlaps = [
            SELECT Id FROM Leave_Request__c
            WHERE Employee__c = :employeeId
            AND Start_Date__c <= :endDate
            AND End_Date__c >= :startDate
            AND Id != :excludeRequestId
            AND Status__c IN ('Submitted', 'Pending_Manager_Approval', 'Pending_HR_Approval', 'Approved')
        ];
        return !overlaps.isEmpty();
    }

    public static void validateBalance(
        Id employeeId,
        String leaveTypeCode,
        Decimal days,
        Date startDate,
        Date endDate,
        Id excludeRequestId
    ) {
        LeaveBalanceLedgerService.validateBalance(
            employeeId,
            null,
            leaveTypeCode,
            startDate,
            endDate,
            excludeRequestId
        );
    }

    public static void handleApprovalResult(Id leaveRequestId, Boolean isApproved) {
        if (isApproved) {
            deductBalance(leaveRequestId);
        } else {
            LeaveBalanceLedgerService.releaseReservedBalance(leaveRequestId, null);
        }
    }

    private static Boolean canCancel(Leave_Request__c req) {
        if (req == null) {
            return false;
        }
        if (req.Status__c == 'Approved') {
            return req.Start_Date__c != null && req.Start_Date__c > System.today();
        }
        return req.Status__c == 'Draft'
            || req.Status__c == 'Submitted'
            || req.Status__c == 'Pending_Manager_Approval'
            || req.Status__c == 'Pending_HR_Approval';
    }

    private static void validateApproverAuthorization(Leave_Request__c req, Id approverId) {
        if (approverId == null) {
            throw new IllegalArgumentException('Approver is required for this action.');
        }
        if (req == null) {
            throw new IllegalArgumentException('Leave request is required for this action.');
        }

        if (req.Status__c == 'Submitted' || req.Status__c == 'Pending_Manager_Approval') {
            if (approverId == getAssignedManagerId(req) ||
                hasPermissionSet(approverId, LEAVE_ADMIN_PERMISSION_SET)) {
                return;
            }
            throw new IllegalArgumentException(
                'Only the assigned manager or leave administrator can approve or reject this request.'
            );
        }

        if (req.Status__c == 'Pending_HR_Approval') {
            applyApprovalSnapshots(req);
            if (hasPermissionSet(approverId, LEAVE_HR_PERMISSION_SET) ||
                hasPermissionSet(approverId, LEAVE_ADMIN_PERMISSION_SET)) {
                return;
            }

            Id configuredApproverId = LeaveApprovalRoutingService.resolveApproverId(
                req,
                'HR_Approval',
                null
            );
            if (configuredApproverId == approverId) {
                return;
            }

            throw new IllegalArgumentException(
                'Only the configured HR approver, HR team, or leave administrator can approve or reject this request.'
            );
        }
    }

    private static Id getAssignedManagerId(Leave_Request__c req) {
        if (req == null) {
            return null;
        }

        Id managerId = toId(getQueriedFieldValue(req, 'Manager__c'));
        if (managerId == null) {
            managerId = queryLeaveRequestIdValue(req.Id, 'Manager__c');
        }
        if (managerId != null) {
            return managerId;
        }

        Id employeeId = toId(getQueriedFieldValue(req, 'Employee__c'));
        if (employeeId == null) {
            employeeId = queryLeaveRequestIdValue(req.Id, 'Employee__c');
        }
        if (employeeId != null) {
            List<User> employees = [
                SELECT ManagerId
                FROM User
                WHERE Id = :employeeId
                LIMIT 1
            ];
            if (!employees.isEmpty()) {
                return employees[0].ManagerId;
            }
        }

        return findPendingApproverId(req.Id);
    }

    private static Boolean hasPermissionSet(Id assigneeId, String permissionSetName) {
        if (assigneeId == null || String.isBlank(permissionSetName)) {
            return false;
        }
        return [
            SELECT COUNT()
            FROM PermissionSetAssignment
            WHERE AssigneeId = :assigneeId
            AND PermissionSet.Name = :permissionSetName
        ] > 0;
    }

    private static void processPendingManagerApproval(Id leaveRequestId, String actionName, String comments) {
        Id workItemId = findPendingWorkItemId(leaveRequestId);
        if (workItemId == null) {
            throw new IllegalArgumentException(
                'No pending manager approval work item was found for this leave request.'
            );
        }

        Approval.ProcessWorkitemRequest workItemRequest = new Approval.ProcessWorkitemRequest();
        workItemRequest.setWorkitemId(workItemId);
        workItemRequest.setAction(actionName);
        if (!String.isBlank(comments)) {
            workItemRequest.setComments(comments);
        }
        Approval.process(workItemRequest);
    }

    private static void insertManagerApprovalHistory(
        Id leaveRequestId,
        Id approverId,
        String actionName,
        String comments
    ) {
        Leave_Approval_History__c history = new Leave_Approval_History__c(
            Leave_Request__c = leaveRequestId,
            Approver__c = approverId,
            Approver_Target__c = 'Manager',
            Approval_Mode_Snapshot__c = queryLeaveRequestStringValue(
                leaveRequestId,
                'Approval_Mode_Snapshot__c'
            ),
            Stage__c = 'Manager_Approval',
            Action__c = actionName,
            Comments__c = comments,
            Action_Time__c = System.now()
        );
        insert history;
    }

    private static Id findPendingWorkItemId(Id leaveRequestId) {
        List<ProcessInstanceWorkitem> workItems = [
            SELECT Id
            FROM ProcessInstanceWorkitem
            WHERE ProcessInstance.TargetObjectId = :leaveRequestId
            AND ProcessInstance.Status = 'Pending'
            ORDER BY CreatedDate DESC
            LIMIT 1
        ];
        return workItems.isEmpty() ? null : workItems[0].Id;
    }

    private static Leave_Request__c loadApprovalRequest(Id leaveRequestId) {
        List<String> selectFields = new List<String>{
            'Id',
            'Status__c'
        };

        String soql =
            'SELECT ' + String.join(selectFields, ', ') +
            ' FROM Leave_Request__c WHERE Id = :leaveRequestId';
        List<Leave_Request__c> requests = Database.query(soql);
        if (requests.isEmpty()) {
            throw new IllegalArgumentException('Leave request was not found.');
        }
        return requests[0];
    }

    private static void applyApprovalSnapshots(Leave_Request__c req) {
        if (req == null || req.Id == null) {
            return;
        }

        String approvalModeSnapshot = queryLeaveRequestStringValue(req.Id, 'Approval_Mode_Snapshot__c');
        if (hasLeaveRequestField('Approval_Mode_Snapshot__c')) {
            req.put('Approval_Mode_Snapshot__c', approvalModeSnapshot);
        }

        String approvalTargetSnapshot = queryLeaveRequestStringValue(req.Id, 'Approval_Target_Snapshot__c');
        if (hasLeaveRequestField('Approval_Target_Snapshot__c')) {
            req.put('Approval_Target_Snapshot__c', approvalTargetSnapshot);
        }
    }

    private static Boolean hasLeaveRequestField(String fieldApiName) {
        return !String.isBlank(fieldApiName) &&
            Leave_Request__c.SObjectType.getDescribe().fields.getMap().containsKey(fieldApiName);
    }

    private static Object getQueriedFieldValue(SObject record, String fieldApiName) {
        if (record == null || !hasLeaveRequestField(fieldApiName)) {
            return null;
        }
        Map<String, Object> populatedFields = record.getPopulatedFieldsAsMap();
        return populatedFields.containsKey(fieldApiName)
            ? populatedFields.get(fieldApiName)
            : null;
    }

    private static Id toId(Object value) {
        if (value == null) {
            return null;
        }
        return (Id)value;
    }

    private static String queryLeaveRequestStringValue(Id leaveRequestId, String fieldApiName) {
        if (leaveRequestId == null || !hasLeaveRequestField(fieldApiName)) {
            return null;
        }

        try {
            String soql =
                'SELECT ' + fieldApiName +
                ' FROM Leave_Request__c WHERE Id = :leaveRequestId';
            List<SObject> records = Database.query(soql);
            if (records.isEmpty()) {
                return null;
            }
            Object value = getQueriedFieldValue(records[0], fieldApiName);
            return value == null ? null : String.valueOf(value);
        } catch (QueryException ex) {
            return null;
        }
    }

    private static Id queryLeaveRequestIdValue(Id leaveRequestId, String fieldApiName) {
        if (leaveRequestId == null || !hasLeaveRequestField(fieldApiName)) {
            return null;
        }

        try {
            String soql =
                'SELECT ' + fieldApiName +
                ' FROM Leave_Request__c WHERE Id = :leaveRequestId';
            List<SObject> records = Database.query(soql);
            if (records.isEmpty()) {
                return null;
            }
            return toId(getQueriedFieldValue(records[0], fieldApiName));
        } catch (QueryException ex) {
            return null;
        }
    }

    private static Id findPendingApproverId(Id leaveRequestId) {
        List<ProcessInstanceWorkitem> workItems = [
            SELECT ActorId
            FROM ProcessInstanceWorkitem
            WHERE ProcessInstance.TargetObjectId = :leaveRequestId
            AND ProcessInstance.Status = 'Pending'
            ORDER BY CreatedDate DESC
            LIMIT 1
        ];
        return workItems.isEmpty() ? null : workItems[0].ActorId;
    }

    private static void recallPendingApprovalIfNeeded(Id leaveRequestId, String comments) {
        Id workItemId = findPendingWorkItemId(leaveRequestId);
        if (workItemId == null) {
            return;
        }

        Approval.ProcessWorkitemRequest recallRequest = new Approval.ProcessWorkitemRequest();
        recallRequest.setWorkitemId(workItemId);
        recallRequest.setAction('Removed');
        if (!String.isBlank(comments)) {
            recallRequest.setComments(comments);
        }
        Approval.process(recallRequest);
    }
}
