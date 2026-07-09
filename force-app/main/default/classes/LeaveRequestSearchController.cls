public with sharing class LeaveRequestSearchController {

    private static final Integer DEFAULT_LIMIT_SIZE = 100;
    private static final Integer MAX_LIMIT_SIZE = 200;
    private static final String SCOPE_MY = 'MY';
    private static final String SCOPE_TEAM = 'TEAM';
    private static final String SCOPE_HR_PENDING = 'HR_PENDING';
    private static final String SCOPE_ALL = 'ALL';

    @AuraEnabled(cacheable=true)
    public static SearchContext getSearchContext() {
        SearchContext context = new SearchContext();
        context.isManager = hasPermissionSet('Leave_Manager') || hasDirectReports();
        context.isHR = hasPermissionSet('Leave_HR') || hasPermissionSet('Leave_Admin');
        context.scopeOptions = buildScopeOptions(context.isManager, context.isHR);
        context.statusOptions = buildStatusOptions();
        return context;
    }

    @AuraEnabled(cacheable=true)
    public static List<LeaveRequestRow> searchLeaveRequests(
        String keyword,
        String employeeKeyword,
        String status,
        String scope,
        Date leaveDateFrom,
        Date leaveDateTo,
        Integer limitSize
    ) {
        Boolean isManager = hasPermissionSet('Leave_Manager') || hasDirectReports();
        Boolean isHR = hasPermissionSet('Leave_HR') || hasPermissionSet('Leave_Admin');
        String normalizedScope = normalizeScope(scope, isManager, isHR);
        Integer effectiveLimit = normalizeLimit(limitSize);
        Id currentUserId = UserInfo.getUserId();
        String keywordLike = buildLikeValue(keyword);
        String employeeKeywordLike = buildLikeValue(employeeKeyword);

        List<String> conditions = new List<String>();
        if (normalizedScope == SCOPE_MY) {
            conditions.add('Employee__c = :currentUserId');
        } else if (normalizedScope == SCOPE_TEAM) {
            conditions.add('Manager__c = :currentUserId');
        } else if (normalizedScope == SCOPE_HR_PENDING) {
            conditions.add('Status__c = \'Pending_HR_Approval\'');
        }

        if (!String.isBlank(status)) {
            conditions.add('Status__c = :status');
        }
        if (keywordLike != null) {
            conditions.add(
                '(Name LIKE :keywordLike OR Leave_Type_Name__c LIKE :keywordLike OR Employee__r.Name LIKE :keywordLike)'
            );
        }
        if (employeeKeywordLike != null) {
            conditions.add('Employee__r.Name LIKE :employeeKeywordLike');
        }
        if (leaveDateFrom != null) {
            conditions.add('End_Date__c >= :leaveDateFrom');
        }
        if (leaveDateTo != null) {
            conditions.add('Start_Date__c <= :leaveDateTo');
        }

        String query =
            'SELECT Id, Name, Employee__c, Employee__r.Name, Manager__c, Manager__r.Name, ' +
            'Leave_Type_Name__c, Start_Date__c, End_Date__c, Days__c, Status__c, Submitted_Time__c, Reason__c ' +
            'FROM Leave_Request__c';
        if (!conditions.isEmpty()) {
            query += ' WHERE ' + String.join(conditions, ' AND ');
        }
        query += ' ORDER BY CreatedDate DESC LIMIT :effectiveLimit';

        List<LeaveRequestRow> rows = new List<LeaveRequestRow>();
        for (Leave_Request__c requestRecord : Database.query(query)) {
            LeaveRequestRow row = new LeaveRequestRow();
            row.requestId = requestRecord.Id;
            row.requestNumber = requestRecord.Name;
            row.employeeId = requestRecord.Employee__c;
            row.employeeName = requestRecord.Employee__r == null ? null : requestRecord.Employee__r.Name;
            row.managerId = requestRecord.Manager__c;
            row.managerName = requestRecord.Manager__r == null ? null : requestRecord.Manager__r.Name;
            row.leaveTypeName = requestRecord.Leave_Type_Name__c;
            row.startDate = requestRecord.Start_Date__c;
            row.endDate = requestRecord.End_Date__c;
            row.days = requestRecord.Days__c;
            row.status = requestRecord.Status__c;
            row.submittedTime = requestRecord.Submitted_Time__c;
            row.reason = requestRecord.Reason__c;
            rows.add(row);
        }
        return rows;
    }

    private static List<OptionItem> buildScopeOptions(Boolean isManager, Boolean isHR) {
        List<OptionItem> options = new List<OptionItem>();
        options.add(buildOption('My Requests', SCOPE_MY));
        if (isManager) {
            options.add(buildOption('Team Requests', SCOPE_TEAM));
        }
        if (isHR) {
            options.add(buildOption('HR Pending', SCOPE_HR_PENDING));
            options.add(buildOption('All Requests', SCOPE_ALL));
        }
        return options;
    }

    private static List<OptionItem> buildStatusOptions() {
        List<OptionItem> options = new List<OptionItem>();
        options.add(buildOption('All Statuses', ''));
        options.add(buildOption('Draft', 'Draft'));
        options.add(buildOption('Submitted', 'Submitted'));
        options.add(buildOption('Pending Manager Approval', 'Pending_Manager_Approval'));
        options.add(buildOption('Pending HR Approval', 'Pending_HR_Approval'));
        options.add(buildOption('Approved', 'Approved'));
        options.add(buildOption('Rejected', 'Rejected'));
        options.add(buildOption('Cancelled', 'Cancelled'));
        return options;
    }

    private static OptionItem buildOption(String label, String value) {
        OptionItem item = new OptionItem();
        item.label = label;
        item.value = value;
        return item;
    }

    private static String normalizeScope(String requestedScope, Boolean isManager, Boolean isHR) {
        if (requestedScope == SCOPE_ALL && isHR) {
            return SCOPE_ALL;
        }
        if (requestedScope == SCOPE_HR_PENDING && isHR) {
            return SCOPE_HR_PENDING;
        }
        if (requestedScope == SCOPE_TEAM && isManager) {
            return SCOPE_TEAM;
        }
        return SCOPE_MY;
    }

    private static Integer normalizeLimit(Integer limitSize) {
        if (limitSize == null || limitSize <= 0) {
            return DEFAULT_LIMIT_SIZE;
        }
        return Math.min(limitSize, MAX_LIMIT_SIZE);
    }

    private static String buildLikeValue(String rawValue) {
        if (String.isBlank(rawValue)) {
            return null;
        }
        return '%' + rawValue.trim() + '%';
    }

    private static Boolean hasPermissionSet(String permissionSetName) {
        if (String.isBlank(permissionSetName)) {
            return false;
        }
        return [
            SELECT COUNT()
            FROM PermissionSetAssignment
            WHERE AssigneeId = :UserInfo.getUserId()
            AND PermissionSet.Name = :permissionSetName
        ] > 0;
    }

    private static Boolean hasDirectReports() {
        return [
            SELECT COUNT()
            FROM User
            WHERE ManagerId = :UserInfo.getUserId()
        ] > 0;
    }

    public class SearchContext {
        @AuraEnabled public Boolean isManager;
        @AuraEnabled public Boolean isHR;
        @AuraEnabled public List<OptionItem> scopeOptions;
        @AuraEnabled public List<OptionItem> statusOptions;
    }

    public class OptionItem {
        @AuraEnabled public String label;
        @AuraEnabled public String value;
    }

    public class LeaveRequestRow {
        @AuraEnabled public Id requestId;
        @AuraEnabled public String requestNumber;
        @AuraEnabled public Id employeeId;
        @AuraEnabled public String employeeName;
        @AuraEnabled public Id managerId;
        @AuraEnabled public String managerName;
        @AuraEnabled public String leaveTypeName;
        @AuraEnabled public Date startDate;
        @AuraEnabled public Date endDate;
        @AuraEnabled public Decimal days;
        @AuraEnabled public String status;
        @AuraEnabled public Datetime submittedTime;
        @AuraEnabled public String reason;
    }
}
