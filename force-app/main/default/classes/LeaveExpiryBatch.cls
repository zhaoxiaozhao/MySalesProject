global class LeaveExpiryBatch implements Database.Batchable<SObject> {

    global Database.QueryLocator start(Database.BatchableContext bc) {
        return Database.getQueryLocator([
            SELECT Id, Status__c, Reason__c, End_Date__c
            FROM Leave_Request__c
            WHERE Status__c IN ('Submitted', 'Pending_Manager_Approval', 'Pending_HR_Approval')
            AND End_Date__c < TODAY
        ]);
    }

    global void execute(Database.BatchableContext bc, List<Leave_Request__c> scope) {
        List<Leave_Request__c> toUpdate = new List<Leave_Request__c>();
        List<Leave_Approval_History__c> histories = new List<Leave_Approval_History__c>();

        for (Leave_Request__c req : scope) {
            req.Status__c = 'Cancelled';
            req.Reason__c = (String.isBlank(req.Reason__c) ? '' : req.Reason__c + '\n')
                + 'Auto-cancelled: leave period ended ' + String.valueOf(req.End_Date__c)
                + ' without approval.';
            toUpdate.add(req);

            histories.add(new Leave_Approval_History__c(
                Leave_Request__c = req.Id,
                Stage__c = 'Cancellation',
                Action__c = 'Cancelled',
                Comments__c = 'Auto-cancelled by system: leave period expired without approval',
                Action_Time__c = System.now()
            ));
        }

        if (!toUpdate.isEmpty()) {
            update toUpdate;
        }
        if (!histories.isEmpty()) {
            insert histories;
        }
    }

    global void finish(Database.BatchableContext bc) {}
}
