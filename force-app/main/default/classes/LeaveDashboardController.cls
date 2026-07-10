public with sharing class LeaveDashboardController {

    private static final Set<String> ACTIVE_STATUSES = new Set<String>{
        'Submitted',
        'Pending_Manager_Approval',
        'Pending_HR_Approval',
        'Approved'
    };
    private static final Integer MAX_REQUEST_SIZE = 500;

    @AuraEnabled(cacheable=true)
    public static CalendarPayload getCalendar(Date referenceDate) {
        Date monthStartDate = referenceDate == null
            ? Date.today().toStartOfMonth()
            : Date.newInstance(referenceDate.year(), referenceDate.month(), 1);
        Date monthEndDate = monthStartDate.addMonths(1).addDays(-1);

        Boolean canAccessHrScope = hasPermissionSet('Leave_HR') || hasPermissionSet('Leave_Admin');
        Set<Id> directReportIds = getDirectReportUserIds(UserInfo.getUserId());
        Boolean canAccessManagerScope = hasPermissionSet('Leave_Manager') || !directReportIds.isEmpty();

        CalendarPayload payload = new CalendarPayload();
        payload.monthStartDate = monthStartDate;
        payload.monthEndDate = monthEndDate;
        payload.isHR = canAccessHrScope;
        payload.isManager = canAccessManagerScope;
        payload.scopeLabel = canAccessHrScope
            ? 'ALL'
            : canAccessManagerScope
                ? 'TEAM'
                : 'MY';
        payload.entries = new List<CalendarEntry>();

        List<Leave_Request__c> requestRecords = [
            SELECT Id, Name, Employee__c, Employee__r.Name, Employee__r.SmallPhotoUrl,
                   Start_Date__c, End_Date__c, Status__c
            FROM Leave_Request__c
            WHERE Status__c IN :ACTIVE_STATUSES
            AND Start_Date__c <= :monthEndDate
            AND End_Date__c >= :monthStartDate
            ORDER BY Start_Date__c ASC, CreatedDate ASC
            LIMIT :MAX_REQUEST_SIZE
        ];

        Set<Id> visibleUserIds = new Set<Id>{ UserInfo.getUserId() };
        if (canAccessManagerScope) {
            visibleUserIds.addAll(directReportIds);
        }

        for (Leave_Request__c requestRecord : requestRecords) {
            if (!canAccessHrScope && !visibleUserIds.contains(requestRecord.Employee__c)) {
                continue;
            }

            CalendarEntry entry = new CalendarEntry();
            entry.requestId = requestRecord.Id;
            entry.requestNumber = requestRecord.Name;
            entry.employeeId = requestRecord.Employee__c;
            entry.employeeName = requestRecord.Employee__r == null ? null : requestRecord.Employee__r.Name;
            entry.employeePhotoUrl = requestRecord.Employee__r == null ? null : requestRecord.Employee__r.SmallPhotoUrl;
            entry.startDate = requestRecord.Start_Date__c;
            entry.endDate = requestRecord.End_Date__c;
            entry.status = requestRecord.Status__c;
            entry.detailUrl = '/lightning/r/Leave_Request__c/' + requestRecord.Id + '/view';
            payload.entries.add(entry);
        }

        return payload;
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

    private static Set<Id> getDirectReportUserIds(Id managerId) {
        Set<Id> directReportIds = new Set<Id>();
        if (managerId == null) {
            return directReportIds;
        }

        for (User directReport : [
            SELECT Id
            FROM User
            WHERE ManagerId = :managerId
        ]) {
            directReportIds.add(directReport.Id);
        }
        return directReportIds;
    }

    public class CalendarPayload {
        @AuraEnabled public Date monthStartDate;
        @AuraEnabled public Date monthEndDate;
        @AuraEnabled public Boolean isManager;
        @AuraEnabled public Boolean isHR;
        @AuraEnabled public String scopeLabel;
        @AuraEnabled public List<CalendarEntry> entries;
    }

    public class CalendarEntry {
        @AuraEnabled public Id requestId;
        @AuraEnabled public String requestNumber;
        @AuraEnabled public Id employeeId;
        @AuraEnabled public String employeeName;
        @AuraEnabled public String employeePhotoUrl;
        @AuraEnabled public Date startDate;
        @AuraEnabled public Date endDate;
        @AuraEnabled public String status;
        @AuraEnabled public String detailUrl;
    }
}
