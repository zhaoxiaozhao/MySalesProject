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
        Leave_Request__c req = [
            SELECT Id, Status__c, Leave_Type_Code__c, Days__c, Manager__c,
                   Approval_Mode_Snapshot__c, Approval_Target_Snapshot__c
            FROM Leave_Request__c
            WHERE Id = :leaveRequestId
        ];

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
        Leave_Request__c req = [
            SELECT Id, Status__c, Manager__c, Approval_Mode_Snapshot__c, Approval_Target_Snapshot__c
            FROM Leave_Request__c
            WHERE Id = :leaveRequestId
        ];

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
            SELECT Id, Employee__c, Status__c, Balance_Deducted__c,
                   Approval_Mode_Snapshot__c, Approval_Target_Snapshot__c
            FROM Leave_Request__c
            WHERE Id = :leaveRequestId
        ];

        if (!canCancel(req)) {
            throw new IllegalArgumentException('Leave request is not in a cancellable status');
        }
        if (req.Balance_Deducted__c) {
            throw new IllegalArgumentException('Approved leave with deducted balance cannot be cancelled here');
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
            if (approverId == req.Manager__c || hasPermissionSet(approverId, LEAVE_ADMIN_PERMISSION_SET)) {
                return;
            }
            throw new IllegalArgumentException(
                'Only the assigned manager or leave administrator can approve or reject this request.'
            );
        }

        if (req.Status__c == 'Pending_HR_Approval') {
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
        Leave_Request__c updatedRequest = [
            SELECT Id, Status__c, Manager__c, Approval_Mode_Snapshot__c, Approval_Target_Snapshot__c
            FROM Leave_Request__c
            WHERE Id = :leaveRequestId
        ];
        Leave_Approval_History__c history = LeaveApprovalHistoryService.buildHistory(
            updatedRequest,
            'Manager_Approval',
            actionName,
            comments
        );
        history.Approver__c = approverId;
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
