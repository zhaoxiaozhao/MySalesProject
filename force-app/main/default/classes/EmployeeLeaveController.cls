public with sharing class EmployeeLeaveController {

    @AuraEnabled(cacheable=true)
    public static Leave_Balance__c getMyBalance() {
        String key = UserInfo.getUserId() + '-' + System.today().year();
        List<Leave_Balance__c> balances = [
            SELECT Id, Annual_Leave__c, Annual_Total_Available__c, Carryover_Annual_Leave__c,
                   Carryover_Expiry_Date__c, Sick_Leave__c, Personal_Leave__c
            FROM Leave_Balance__c
            WHERE Unique_Key__c = :key
        ];
        return balances.isEmpty() ? null : balances[0];
    }

    @AuraEnabled(cacheable=true)
    public static List<Leave_Request__c> getMyRequests() {
        return [
            SELECT Id, Name, Leave_Type__c, Start_Date__c, End_Date__c,
                   Days__c, Status__c, Submitted_Time__c, Reason__c
            FROM Leave_Request__c
            WHERE Employee__c = :UserInfo.getUserId()
            ORDER BY CreatedDate DESC
            LIMIT 50
        ];
    }
}
