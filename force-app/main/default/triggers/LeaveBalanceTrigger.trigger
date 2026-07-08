trigger LeaveBalanceTrigger on Leave_Balance__c (before insert) {
    for (Leave_Balance__c bal : Trigger.new) {
        if (bal.User__c != null && bal.Year__c != null && String.isBlank(bal.Unique_Key__c)) {
            bal.Unique_Key__c = bal.User__c + '-' + bal.Year__c;
        }
    }
}
