public without sharing class LeaveApprovalHistoryService {

    private static Boolean transitionHistorySuppressed = false;

    public static void suppressTransitionHistory(Boolean isSuppressed) {
        transitionHistorySuppressed = isSuppressed;
    }

    public static Boolean isTransitionHistorySuppressed() {
        return transitionHistorySuppressed;
    }

    public static void createTransitionHistories(
        List<Leave_Request__c> records,
        Map<Id, Leave_Request__c> oldMap
    ) {
        List<Leave_Approval_History__c> historiesToInsert = new List<Leave_Approval_History__c>();
        for (Leave_Request__c requestRecord : records) {
            Leave_Request__c oldRecord = oldMap.get(requestRecord.Id);
            if (oldRecord == null) {
                continue;
            }

            if (isDraftSubmission(oldRecord, requestRecord)) {
                historiesToInsert.add(buildHistory(requestRecord, 'Submit', 'Submitted', null));
                if (requestRecord.Status__c == 'Approved' &&
                    requestRecord.Approval_Mode_Snapshot__c == 'Auto Approve') {
                    historiesToInsert.add(
                        buildHistory(requestRecord, 'Submit', 'Approved', 'Auto approved by policy.')
                    );
                }
            }

            if (oldRecord.Status__c == 'Pending_Manager_Approval' && requestRecord.Status__c == 'Pending_HR_Approval') {
                historiesToInsert.add(buildHistory(requestRecord, 'Manager_Approval', 'Approved', null));
            } else if (oldRecord.Status__c == 'Pending_Manager_Approval' && requestRecord.Status__c == 'Approved') {
                historiesToInsert.add(buildHistory(requestRecord, 'Manager_Approval', 'Approved', null));
            } else if (oldRecord.Status__c == 'Pending_HR_Approval' && requestRecord.Status__c == 'Approved') {
                historiesToInsert.add(buildHistory(requestRecord, 'HR_Approval', 'Approved', null));
            } else if (oldRecord.Status__c == 'Pending_Manager_Approval' && requestRecord.Status__c == 'Rejected') {
                historiesToInsert.add(buildHistory(requestRecord, 'Manager_Approval', 'Rejected', null));
            } else if (oldRecord.Status__c == 'Pending_HR_Approval' && requestRecord.Status__c == 'Rejected') {
                historiesToInsert.add(buildHistory(requestRecord, 'HR_Approval', 'Rejected', null));
            }
        }

        if (!historiesToInsert.isEmpty()) {
            insert historiesToInsert;
        }
    }

    public static Leave_Approval_History__c buildHistory(
        Leave_Request__c requestRecord,
        String stage,
        String action,
        String comments
    ) {
        return new Leave_Approval_History__c(
            Leave_Request__c = requestRecord.Id,
            Approver__c = LeaveApprovalRoutingService.resolveApproverId(requestRecord, stage, action),
            Approver_Target__c = LeaveApprovalRoutingService.resolveApproverTarget(requestRecord, stage, action),
            Approval_Mode_Snapshot__c = requestRecord.Approval_Mode_Snapshot__c,
            Stage__c = stage,
            Action__c = action,
            Comments__c = comments,
            Action_Time__c = System.now()
        );
    }

    private static Boolean isDraftSubmission(Leave_Request__c oldRecord, Leave_Request__c requestRecord) {
        return oldRecord.Status__c == 'Draft'
            && requestRecord.Status__c != 'Draft'
            && requestRecord.Status__c != null;
    }
}
