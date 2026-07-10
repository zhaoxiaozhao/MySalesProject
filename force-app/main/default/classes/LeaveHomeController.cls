public with sharing class LeaveHomeController {

    private static final Set<String> REQUEST_ENABLED_TYPE_CODES = new Set<String>{
        'ANNUAL', 'SICK', 'PERSONAL'
    };
    private static Set<String> nonQueryableRequestFields = new Set<String>();

    @AuraEnabled(cacheable=true)
    public static RoleInfo getUserRoles() {
        RoleInfo info = new RoleInfo();
        info.isManager = canAccessManagerScope();
        info.isHR = canAccessHrScope();
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
        return queryLeaveRequests(
            new List<String>{
                'Id',
                'Name',
                'Leave_Type_Name__c',
                'Leave_Type_Definition__r.Name',
                'Start_Date__c',
                'End_Date__c',
                'Days__c',
                'Status__c',
                'Submitted_Time__c',
                'Reason__c',
                'Balance_Deducted__c'
            },
            'Employee__c = ' + toSoqlLiteral(UserInfo.getUserId()) +
                ' AND Status__c IN (\'Draft\', \'Submitted\', \'Pending_Manager_Approval\', \'Pending_HR_Approval\')',
            50
        );
    }

    @AuraEnabled
    public static List<Leave_Request__c> getPendingApprovals() {
        if (!canAccessManagerScope()) {
            return new List<Leave_Request__c>();
        }
        Set<Id> directReportIds = getDirectReportUserIds(UserInfo.getUserId());
        if (directReportIds.isEmpty()) {
            return new List<Leave_Request__c>();
        }
        List<Leave_Request__c> pendingCandidates = queryLeaveRequests(
            new List<String>{
                'Id',
                'Name',
                'Leave_Type_Name__c',
                'Leave_Type_Definition__r.Name',
                'Start_Date__c',
                'End_Date__c',
                'Days__c',
                'Status__c',
                'Employee__c',
                'Employee__r.Name'
            },
            'Status__c IN (\'Submitted\', \'Pending_Manager_Approval\')',
            200
        );

        List<Leave_Request__c> pendingApprovals = new List<Leave_Request__c>();
        for (Leave_Request__c requestRecord : pendingCandidates) {
            Id employeeId = getLeaveRequestIdValue(requestRecord, 'Employee__c');
            if (employeeId != null) {
                requestRecord.put('Employee__c', employeeId);
            }
            if (directReportIds.contains(employeeId)) {
                pendingApprovals.add(requestRecord);
            }
            if (pendingApprovals.size() == 50) {
                break;
            }
        }
        return pendingApprovals;
    }

    @AuraEnabled
    public static List<Leave_Request__c> getHrPendingApprovals() {
        if (!canAccessHrScope()) {
            return new List<Leave_Request__c>();
        }
        return queryLeaveRequests(
            new List<String>{
                'Id',
                'Name',
                'Leave_Type_Name__c',
                'Leave_Type_Definition__r.Name',
                'Start_Date__c',
                'End_Date__c',
                'Days__c',
                'Status__c',
                'Employee__c',
                'Employee__r.Name'
            },
            'Status__c = \'Pending_HR_Approval\'',
            50
        );
    }

    @AuraEnabled
    public static List<Leave_Request__c> getAllRequests() {
        if (!canAccessHrScope()) {
            return new List<Leave_Request__c>();
        }
        return queryLeaveRequests(
            new List<String>{
                'Id',
                'Name',
                'Leave_Type_Name__c',
                'Leave_Type_Definition__r.Name',
                'Start_Date__c',
                'End_Date__c',
                'Days__c',
                'Status__c',
                'Employee__c',
                'Employee__r.Name'
            },
            null,
            200
        );
    }

    @AuraEnabled
    public static List<LeaveBalanceLedgerService.BalanceSummary> getAllBalances() {
        if (!canAccessHrScope()) {
            return new List<LeaveBalanceLedgerService.BalanceSummary>();
        }
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

    private static Boolean canAccessManagerScope() {
        return hasPermissionSet('Leave_Manager') || hasDirectReports();
    }

    private static Boolean canAccessHrScope() {
        return hasPermissionSet('Leave_HR') || hasPermissionSet('Leave_Admin');
    }

    private static Boolean hasDirectReports() {
        return !getDirectReportUserIds(UserInfo.getUserId()).isEmpty();
    }

    private static List<Leave_Request__c> queryLeaveRequests(
        List<String> requestedFields,
        String whereClause,
        Integer limitSize
    ) {
        while (true) {
            List<String> selectFields = new List<String>();
            Set<String> addedFields = new Set<String>();
            for (String requestedField : requestedFields) {
                addLeaveRequestFieldIfQueryable(selectFields, addedFields, requestedField);
            }

            String soql = 'SELECT ' + String.join(selectFields, ', ') + ' FROM Leave_Request__c';
            if (!String.isBlank(whereClause)) {
                soql += ' WHERE ' + whereClause;
            }
            soql += ' ORDER BY CreatedDate DESC';
            if (limitSize != null && limitSize > 0) {
                soql += ' LIMIT ' + String.valueOf(limitSize);
            }

            try {
                List<Leave_Request__c> requests = new List<Leave_Request__c>();
                for (SObject record : Database.query(soql)) {
                    requests.add((Leave_Request__c)record);
                }
                return requests;
            } catch (QueryException ex) {
                String missingFieldApiName = extractMissingFieldApiName(ex);
                if (String.isBlank(missingFieldApiName) ||
                    !markRequestFieldAsNonQueryable(requestedFields, missingFieldApiName)) {
                    throw ex;
                }
            }
        }
        return new List<Leave_Request__c>();
    }

    private static String toSoqlLiteral(Object value) {
        return value == null
            ? 'null'
            : '\'' + String.escapeSingleQuotes(String.valueOf(value)) + '\'';
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

    private static void addLeaveRequestFieldIfQueryable(
        List<String> selectFields,
        Set<String> addedFields,
        String fieldPath
    ) {
        String normalizedFieldPath = normalizeLeaveRequestFieldPath(fieldPath);
        if (String.isBlank(normalizedFieldPath)) {
            return;
        }

        Integer relationSeparatorIndex = normalizedFieldPath.indexOf('.');
        String rootFieldApiName = relationSeparatorIndex > -1
            ? relationshipTokenToLookupFieldApiName(
                normalizedFieldPath.substring(0, relationSeparatorIndex)
            )
            : normalizedFieldPath;
        if (!hasLeaveRequestField(rootFieldApiName) ||
            nonQueryableRequestFields.contains(rootFieldApiName) ||
            nonQueryableRequestFields.contains(normalizedFieldPath) ||
            addedFields.contains(normalizedFieldPath)) {
            return;
        }

        selectFields.add(normalizedFieldPath);
        addedFields.add(normalizedFieldPath);
    }

    private static String normalizeLeaveRequestFieldPath(String fieldPath) {
        if (String.isBlank(fieldPath)) {
            return null;
        }

        Integer relationSeparatorIndex = fieldPath.indexOf('.');
        if (relationSeparatorIndex < 0) {
            return fieldPath;
        }

        String relationshipToken = fieldPath.substring(0, relationSeparatorIndex);
        String childFieldPath = fieldPath.substring(relationSeparatorIndex + 1);
        String lookupFieldApiName = relationshipTokenToLookupFieldApiName(relationshipToken);
        if (!hasLeaveRequestField(lookupFieldApiName)) {
            return null;
        }

        Schema.DescribeFieldResult describeResult =
            Leave_Request__c.SObjectType.getDescribe().fields.getMap().get(lookupFieldApiName).getDescribe();
        String relationshipName = describeResult.getRelationshipName();
        if (String.isBlank(relationshipName)) {
            return null;
        }
        return relationshipName + '.' + childFieldPath;
    }

    private static String relationshipTokenToLookupFieldApiName(String relationshipToken) {
        if (String.isBlank(relationshipToken)) {
            return null;
        }
        if (relationshipToken.endsWith('__r')) {
            return relationshipToken.substring(0, relationshipToken.length() - 3) + '__c';
        }
        return relationshipToken;
    }

    private static Boolean hasLeaveRequestField(String fieldApiName) {
        return !String.isBlank(fieldApiName) &&
            Leave_Request__c.SObjectType.getDescribe().fields.getMap().containsKey(fieldApiName);
    }

    private static Id getLeaveRequestIdValue(Leave_Request__c requestRecord, String fieldApiName) {
        if (requestRecord == null || String.isBlank(fieldApiName)) {
            return null;
        }

        Map<String, Object> populatedFields = requestRecord.getPopulatedFieldsAsMap();
        if (populatedFields.containsKey(fieldApiName)) {
            return (Id)populatedFields.get(fieldApiName);
        }
        return queryLeaveRequestIdValue(requestRecord.Id, fieldApiName);
    }

    private static Id queryLeaveRequestIdValue(Id leaveRequestId, String fieldApiName) {
        if (leaveRequestId == null || !hasLeaveRequestField(fieldApiName)) {
            return null;
        }

        try {
            String soql =
                'SELECT ' + fieldApiName +
                ' FROM Leave_Request__c WHERE Id = :leaveRequestId';
            List<SObject> records = Database.query(soql);
            if (records.isEmpty()) {
                return null;
            }
            return (Id)records[0].get(fieldApiName);
        } catch (QueryException ex) {
            return null;
        }
    }

    private static Boolean markRequestFieldAsNonQueryable(
        List<String> requestedFields,
        String missingFieldApiName
    ) {
        if (String.isBlank(missingFieldApiName) || nonQueryableRequestFields.contains(missingFieldApiName)) {
            return false;
        }

        Boolean matchedRequestedField = false;
        for (String requestedField : requestedFields) {
            if (requestedField == missingFieldApiName ||
                requestedField.startsWith(missingFieldApiName + '.')) {
                matchedRequestedField = true;
                nonQueryableRequestFields.add(requestedField);
            }
        }
        if (matchedRequestedField) {
            nonQueryableRequestFields.add(missingFieldApiName);
        }
        return matchedRequestedField;
    }

    private static String extractMissingFieldApiName(QueryException ex) {
        String message = ex == null ? null : ex.getMessage();
        if (String.isBlank(message)) {
            return null;
        }

        String prefix = 'No such column \'';
        Integer prefixIndex = message.indexOf(prefix);
        if (prefixIndex < 0) {
            return null;
        }

        Integer fieldStartIndex = prefixIndex + prefix.length();
        Integer fieldEndIndex = message.indexOf('\'', fieldStartIndex);
        if (fieldEndIndex <= fieldStartIndex) {
            return null;
        }
        return message.substring(fieldStartIndex, fieldEndIndex);
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
