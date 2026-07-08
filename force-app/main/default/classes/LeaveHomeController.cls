public with sharing class LeaveHomeController {

    @AuraEnabled(cacheable=true)
    public static RoleInfo getUserRoles() {
        RoleInfo info = new RoleInfo();
        info.isManager = hasPermissionSet('Leave_Manager');
        info.isHR = hasPermissionSet('Leave_HR');
        info.isEmployee = !info.isManager && !info.isHR;
        return info;
    }

    @AuraEnabled(cacheable=true)
    public static Leave_Balance__c getMyBalance() {
        String key = UserInfo.getUserId() + '-' + System.today().year();
        List<Leave_Balance__c> balances = [
            SELECT Id, Annual_Leave__c, Annual_Total_Available__c, Carryover_Annual_Leave__c,
                   Carryover_Expiry_Date__c, Sick_Leave__c, Personal_Leave__c
            FROM Leave_Balance__c WHERE Unique_Key__c = :key
        ];
        return balances.isEmpty() ? null : balances[0];
    }

    @AuraEnabled(cacheable=true)
    public static List<Leave_Request__c> getMyRequests() {
        return [
            SELECT Id, Name, Leave_Type__c, Start_Date__c, End_Date__c,
                   Days__c, Status__c, Submitted_Time__c, Reason__c
            FROM Leave_Request__c WHERE Employee__c = :UserInfo.getUserId()
            ORDER BY CreatedDate DESC LIMIT 50
        ];
    }

    @AuraEnabled(cacheable=true)
    public static List<Leave_Request__c> getPendingApprovals() {
        return [
            SELECT Id, Name, Leave_Type__c, Start_Date__c, End_Date__c,
                   Days__c, Status__c, Employee__c, Employee__r.Name
            FROM Leave_Request__c
            WHERE Manager__c = :UserInfo.getUserId()
            AND Status__c IN ('Submitted', 'Pending_Manager_Approval')
            ORDER BY CreatedDate DESC LIMIT 50
        ];
    }

    @AuraEnabled(cacheable=true)
    public static List<Leave_Request__c> getAllRequests() {
        return [
            SELECT Id, Name, Leave_Type__c, Start_Date__c, End_Date__c,
                   Days__c, Status__c, Employee__c, Employee__r.Name
            FROM Leave_Request__c
            ORDER BY CreatedDate DESC LIMIT 200
        ];
    }

    @AuraEnabled(cacheable=true)
    public static List<Leave_Balance__c> getAllBalances() {
        return [
            SELECT Id, Name, User__c, User__r.Name, Year__c,
                   Annual_Leave__c, Annual_Total_Available__c, Carryover_Annual_Leave__c,
                   Carryover_Expiry_Date__c, Sick_Leave__c, Personal_Leave__c
            FROM Leave_Balance__c ORDER BY Year__c DESC, User__r.Name LIMIT 200
        ];
    }

    private static Boolean hasPermissionSet(String name) {
        return [SELECT COUNT() FROM PermissionSetAssignment
            WHERE AssigneeId = :UserInfo.getUserId()
            AND PermissionSet.Name = :name] > 0;
    }

    public class RoleInfo {
        @AuraEnabled public Boolean isEmployee;
        @AuraEnabled public Boolean isManager;
        @AuraEnabled public Boolean isHR;
    }
}
