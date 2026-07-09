public without sharing class LeaveService {

    public static void submitLeave(Id leaveRequestId) {
        Leave_Request__c req = [
            SELECT Id, Employee__c, Manager__c, Start_Date__c, End_Date__c,
                   Days__c, Leave_Type_Code__c, Status__c, Approval_Mode_Snapshot__c,
                   Approval_Target_Snapshot__c
            FROM Leave_Request__c
            WHERE Id = :leaveRequestId
        ];

        User emp = [SELECT Id, ManagerId FROM User WHERE Id = :req.Employee__c];

        req.Manager__c = emp.ManagerId;
        req.Status__c = 'Pending_Manager_Approval';
        req.Submitted_Time__c = System.now();
        LeaveApprovalHistoryService.suppressTransitionHistory(true);
        try {
            update req;
        } finally {
            LeaveApprovalHistoryService.suppressTransitionHistory(false);
        }

        Leave_Request__c submittedRequest = [
            SELECT Id, Status__c, Manager__c, Approval_Mode_Snapshot__c,
                   Approval_Target_Snapshot__c, Balance_Deducted__c
            FROM Leave_Request__c
            WHERE Id = :req.Id
        ];

        List<Leave_Approval_History__c> historiesToInsert = new List<Leave_Approval_History__c>();
        historiesToInsert.add(
            LeaveApprovalHistoryService.buildHistory(submittedRequest, 'Submit', 'Submitted', null)
        );
        if (submittedRequest.Status__c == 'Approved' &&
            submittedRequest.Approval_Mode_Snapshot__c == 'Auto Approve') {
            historiesToInsert.add(
                LeaveApprovalHistoryService.buildHistory(
                    submittedRequest,
                    'Submit',
                    'Approved',
                    'Auto approved by policy.'
                )
            );
        }
        insert historiesToInsert;

        if (submittedRequest.Status__c == 'Pending_Manager_Approval') {
            Approval.ProcessSubmitRequest submitReq = new Approval.ProcessSubmitRequest();
            submitReq.setObjectId(req.Id);
            submitReq.setSubmitterId(UserInfo.getUserId());
            Approval.process(submitReq);
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
        if (req.Status__c == 'Pending_Manager_Approval') {
            nextStatus = 'Approved';
            stage = 'Manager_Approval';
        } else if (req.Status__c == 'Pending_HR_Approval') {
            nextStatus = 'Approved';
            stage = 'HR_Approval';
        } else {
            throw new IllegalArgumentException('Leave request is not in an approvable status');
        }

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

        if (req.Status__c != 'Pending_Manager_Approval' && req.Status__c != 'Pending_HR_Approval') {
            throw new IllegalArgumentException('Leave request is not in a rejectable status');
        }

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

    private static void recallPendingApprovalIfNeeded(Id leaveRequestId, String comments) {
        List<ProcessInstanceWorkitem> workItems = [
            SELECT Id
            FROM ProcessInstanceWorkitem
            WHERE ProcessInstance.TargetObjectId = :leaveRequestId
            AND ProcessInstance.Status = 'Pending'
            ORDER BY CreatedDate DESC
            LIMIT 1
        ];
        if (workItems.isEmpty()) {
            return;
        }

        Approval.ProcessWorkitemRequest recallRequest = new Approval.ProcessWorkitemRequest();
        recallRequest.setWorkitemId(workItems[0].Id);
        recallRequest.setAction('Removed');
        if (!String.isBlank(comments)) {
            recallRequest.setComments(comments);
        }
        Approval.process(recallRequest);
    }
}
