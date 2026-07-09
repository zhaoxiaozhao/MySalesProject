trigger LeaveBalanceTrigger on Leave_Balance__c (before insert, after insert) {
    if (Trigger.isBefore && Trigger.isInsert) {
        for (Leave_Balance__c bal : Trigger.new) {
            if (bal.Balance_Year__c == null && bal.Year__c != null) {
                bal.Balance_Year__c = bal.Year__c;
            } else if (bal.Year__c == null && bal.Balance_Year__c != null) {
                bal.Year__c = bal.Balance_Year__c;
            }

            if (String.isBlank(bal.Status__c)) {
                bal.Status__c = 'Open';
            }
            if (bal.User__c != null && bal.Year__c != null && String.isBlank(bal.Unique_Key__c)) {
                bal.Unique_Key__c = bal.User__c + '-' + bal.Year__c;
            }
        }
    }

    if (Trigger.isAfter && Trigger.isInsert) {
        LeaveBalanceLedgerService.initializeLinesFromBalanceHeads(Trigger.newMap.keySet());
    }
}
