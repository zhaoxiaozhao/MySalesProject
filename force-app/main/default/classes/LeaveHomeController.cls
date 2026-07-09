public with sharing class LeaveHomeController {

    private static final Set<String> REQUEST_ENABLED_TYPE_CODES = new Set<String>{
        'ANNUAL', 'SICK', 'PERSONAL'
    };

    @AuraEnabled(cacheable=true)
    public static RoleInfo getUserRoles() {
        RoleInfo info = new RoleInfo();
        info.isManager = hasPermissionSet('Leave_Manager') || hasDirectReports();
        info.isHR = hasPermissionSet('Leave_HR') || hasPermissionSet('Leave_Admin');
        info.isEmployee = true;
        return info;
    }

    @AuraEnabled
    public static LeaveBalanceLedgerService.BalanceSummary getMyBalance() {
        return LeaveBalanceLedgerService.getUserBalanceSummary(
            UserInfo.getUserId(),
            System.today().year()
        );
    }

    @AuraEnabled
    public static List<Leave_Request__c> getMyRequests() {
        return [
            SELECT Id, Name, Leave_Type_Name__c, Start_Date__c, End_Date__c,
                   Days__c, Status__c, Submitted_Time__c, Reason__c, Balance_Deducted__c
            FROM Leave_Request__c WHERE Employee__c = :UserInfo.getUserId()
            ORDER BY CreatedDate DESC LIMIT 50
        ];
    }

    @AuraEnabled
    public static List<Leave_Request__c> getPendingApprovals() {
        return [
            SELECT Id, Name, Leave_Type_Name__c, Start_Date__c, End_Date__c,
                   Days__c, Status__c, Employee__c, Employee__r.Name
            FROM Leave_Request__c
            WHERE Manager__c = :UserInfo.getUserId()
            AND Status__c IN ('Submitted', 'Pending_Manager_Approval')
            ORDER BY CreatedDate DESC LIMIT 50
        ];
    }

    @AuraEnabled
    public static List<Leave_Request__c> getHrPendingApprovals() {
        return [
            SELECT Id, Name, Leave_Type_Name__c, Start_Date__c, End_Date__c,
                   Days__c, Status__c, Employee__c, Employee__r.Name
            FROM Leave_Request__c
            WHERE Status__c = 'Pending_HR_Approval'
            ORDER BY CreatedDate DESC LIMIT 50
        ];
    }

    @AuraEnabled
    public static List<Leave_Request__c> getAllRequests() {
        return [
            SELECT Id, Name, Leave_Type_Name__c, Start_Date__c, End_Date__c,
                   Days__c, Status__c, Employee__c, Employee__r.Name
            FROM Leave_Request__c
            ORDER BY CreatedDate DESC LIMIT 200
        ];
    }

    @AuraEnabled
    public static List<LeaveBalanceLedgerService.BalanceSummary> getAllBalances() {
        return LeaveBalanceLedgerService.getAllBalanceSummaries(200);
    }

    @AuraEnabled(cacheable=true)
    public static List<LeaveTypeOption> getAvailableLeaveTypes() {
        List<LeaveTypeOption> options = new List<LeaveTypeOption>();
        for (Leave_Type_Definition__c definitionRecord : [
            SELECT Id, Name, Type_Code__c, Approval_Mode__c
            FROM Leave_Type_Definition__c
            WHERE Is_Active__c = true
            AND Type_Code__c IN :REQUEST_ENABLED_TYPE_CODES
            ORDER BY Name
        ]) {
            LeaveTypeOption option = new LeaveTypeOption();
            option.definitionId = definitionRecord.Id;
            option.typeCode = definitionRecord.Type_Code__c;
            option.label = definitionRecord.Name;
            option.approvalMode = definitionRecord.Approval_Mode__c;
            options.add(option);
        }
        return options;
    }

    @AuraEnabled
    public static Id createLeaveRequest(
        Id leaveTypeDefinitionId,
        Date startDate,
        Date endDate,
        String reason
    ) {
        if (leaveTypeDefinitionId == null) {
            throw new AuraHandledException('Please select a leave type.');
        }
        if (startDate == null || endDate == null) {
            throw new AuraHandledException('Start date and end date are required.');
        }
        if (endDate < startDate) {
            throw new AuraHandledException('End date cannot be earlier than start date.');
        }

        Leave_Type_Definition__c definitionRecord;
        List<Leave_Type_Definition__c> definitions = [
            SELECT Id, Name, Type_Code__c, Is_Active__c
            FROM Leave_Type_Definition__c
            WHERE Id = :leaveTypeDefinitionId
            LIMIT 1
        ];
        if (definitions.isEmpty()) {
            throw new AuraHandledException('Selected leave type definition does not exist.');
        }

        definitionRecord = definitions[0];
        if (!definitionRecord.Is_Active__c) {
            throw new AuraHandledException('Selected leave type is inactive.');
        }
        if (!REQUEST_ENABLED_TYPE_CODES.contains(definitionRecord.Type_Code__c)) {
            throw new AuraHandledException(
                'Selected leave type is not yet enabled for self-service request creation.'
            );
        }

        Leave_Request__c requestRecord = new Leave_Request__c(
            Employee__c = UserInfo.getUserId(),
            Leave_Type_Definition__c = leaveTypeDefinitionId,
            Start_Date__c = startDate,
            End_Date__c = endDate,
            Status__c = 'Draft',
            Balance_Deducted__c = false,
            Reason__c = reason
        );
        insert requestRecord;
        return requestRecord.Id;
    }

    @AuraEnabled
    public static void submitLeaveAction(Id leaveRequestId) {
        try {
            validateEmployeeRequestOwnership(leaveRequestId);
            LeaveService.submitLeave(leaveRequestId);
        } catch (AuraHandledException ex) {
            throw ex;
        } catch (DmlException ex) {
            throw new AuraHandledException(extractUserMessage(ex));
        } catch (IllegalArgumentException ex) {
            throw new AuraHandledException(ex.getMessage());
        } catch (Exception ex) {
            throw new AuraHandledException(buildUnexpectedActionMessage('submit leave request', ex));
        }
    }

    @AuraEnabled
    public static void cancelLeaveAction(Id leaveRequestId) {
        try {
            validateEmployeeRequestOwnership(leaveRequestId);
            LeaveService.cancelLeave(leaveRequestId, UserInfo.getUserId(), 'Cancelled by employee from leave home');
        } catch (AuraHandledException ex) {
            throw ex;
        } catch (DmlException ex) {
            throw new AuraHandledException(extractUserMessage(ex));
        } catch (IllegalArgumentException ex) {
            throw new AuraHandledException(ex.getMessage());
        } catch (Exception ex) {
            throw new AuraHandledException(buildUnexpectedActionMessage('cancel leave request', ex));
        }
    }

    @AuraEnabled
    public static void approveLeaveAction(Id leaveRequestId) {
        try {
            LeaveService.approveLeave(leaveRequestId, UserInfo.getUserId(), null);
        } catch (AuraHandledException ex) {
            throw ex;
        } catch (DmlException ex) {
            throw new AuraHandledException(extractUserMessage(ex));
        } catch (IllegalArgumentException ex) {
            throw new AuraHandledException(ex.getMessage());
        } catch (Exception ex) {
            throw new AuraHandledException(buildUnexpectedActionMessage('approve leave request', ex));
        }
    }

    @AuraEnabled
    public static void rejectLeaveAction(Id leaveRequestId) {
        try {
            LeaveService.rejectLeave(leaveRequestId, UserInfo.getUserId(), null);
        } catch (AuraHandledException ex) {
            throw ex;
        } catch (DmlException ex) {
            throw new AuraHandledException(extractUserMessage(ex));
        } catch (IllegalArgumentException ex) {
            throw new AuraHandledException(ex.getMessage());
        } catch (Exception ex) {
            throw new AuraHandledException(buildUnexpectedActionMessage('reject leave request', ex));
        }
    }

    private static Boolean hasPermissionSet(String name) {
        return [SELECT COUNT() FROM PermissionSetAssignment
            WHERE AssigneeId = :UserInfo.getUserId()
            AND PermissionSet.Name = :name] > 0;
    }

    private static Boolean hasDirectReports() {
        return [SELECT COUNT() FROM User WHERE ManagerId = :UserInfo.getUserId()] > 0;
    }

    private static void validateEmployeeRequestOwnership(Id leaveRequestId) {
        Leave_Request__c req = [
            SELECT Employee__c
            FROM Leave_Request__c
            WHERE Id = :leaveRequestId
        ];
        if (req.Employee__c != UserInfo.getUserId()) {
            throw new AuraHandledException('You can only operate your own leave request.');
        }
    }

    private static String extractUserMessage(DmlException ex) {
        if (ex == null) {
            return 'Operation failed.';
        }
        if (ex.getNumDml() > 0) {
            String dmlMessage = ex.getDmlMessage(0);
            if (!String.isBlank(dmlMessage)) {
                return dmlMessage;
            }
        }
        if (!String.isBlank(ex.getMessage())) {
            return ex.getMessage();
        }
        return 'Operation failed.';
    }

    private static String buildUnexpectedActionMessage(String actionLabel, Exception ex) {
        String safeMessage = ex == null ? null : ex.getMessage();
        if (String.isBlank(safeMessage)) {
            return 'Failed to ' + actionLabel + '.';
        }
        return 'Failed to ' + actionLabel + ': ' + safeMessage;
    }

    public class RoleInfo {
        @AuraEnabled public Boolean isEmployee;
        @AuraEnabled public Boolean isManager;
        @AuraEnabled public Boolean isHR;
    }

    public class LeaveTypeOption {
        @AuraEnabled public Id definitionId;
        @AuraEnabled public String typeCode;
        @AuraEnabled public String label;
        @AuraEnabled public String approvalMode;
    }
}
