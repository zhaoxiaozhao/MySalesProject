public without sharing class LeaveService {

    private static Boolean isProcessing = false;

    public static void submitLeave(Id leaveRequestId) {
        Leave_Request__c req = [
            SELECT Id, Employee__c, Manager__c, Start_Date__c, End_Date__c,
                   Days__c, Leave_Type__c, Status__c, Approval_Mode_Snapshot__c,
                   Approval_Target_Snapshot__c
            FROM Leave_Request__c
            WHERE Id = :leaveRequestId
        ];

        User emp = [SELECT Id, ManagerId FROM User WHERE Id = :req.Employee__c];

        req.Manager__c = emp.ManagerId;
        req.Status__c = 'Pending_Manager_Approval';
        req.Submitted_Time__c = System.now();
        LeaveApprovalHistoryService.suppressTransitionHistory(true);
        try {
            update req;
        } finally {
            LeaveApprovalHistoryService.suppressTransitionHistory(false);
        }

        Leave_Request__c submittedRequest = [
            SELECT Id, Status__c, Manager__c, Approval_Mode_Snapshot__c,
                   Approval_Target_Snapshot__c, Balance_Deducted__c
            FROM Leave_Request__c
            WHERE Id = :req.Id
        ];

        List<Leave_Approval_History__c> historiesToInsert = new List<Leave_Approval_History__c>();
        historiesToInsert.add(
            LeaveApprovalHistoryService.buildHistory(submittedRequest, 'Submit', 'Submitted', null)
        );
        if (submittedRequest.Status__c == 'Approved' &&
            submittedRequest.Approval_Mode_Snapshot__c == 'Auto Approve') {
            historiesToInsert.add(
                LeaveApprovalHistoryService.buildHistory(
                    submittedRequest,
                    'Submit',
                    'Approved',
                    'Auto approved by policy.'
                )
            );
        }
        insert historiesToInsert;

        if (submittedRequest.Status__c == 'Pending_Manager_Approval') {
            Approval.ProcessSubmitRequest submitReq = new Approval.ProcessSubmitRequest();
            submitReq.setObjectId(req.Id);
            submitReq.setSubmitterId(UserInfo.getUserId());
            Approval.process(submitReq);
        }
    }

    public static void approveLeave(Id leaveRequestId, Id approverId, String comments) {
        Leave_Request__c req = [
            SELECT Id, Status__c, Leave_Type__c, Days__c, Manager__c,
                   Approval_Mode_Snapshot__c, Approval_Target_Snapshot__c
            FROM Leave_Request__c
            WHERE Id = :leaveRequestId
        ];

        String nextStatus;
        String stage;
        if (req.Status__c == 'Pending_Manager_Approval') {
            nextStatus = 'Approved';
            stage = 'Manager_Approval';
        } else if (req.Status__c == 'Pending_HR_Approval') {
            nextStatus = 'Approved';
            stage = 'HR_Approval';
        } else {
            throw new IllegalArgumentException('Leave request is not in an approvable status');
        }

        req.Status__c = nextStatus;
        LeaveApprovalHistoryService.suppressTransitionHistory(true);
        try {
            update req;
        } finally {
            LeaveApprovalHistoryService.suppressTransitionHistory(false);
        }

        Leave_Approval_History__c history = LeaveApprovalHistoryService.buildHistory(req, stage, 'Approved', comments);
        history.Approver__c = approverId;
        insert history;

        Leave_Request__c updatedRequest = [
            SELECT Status__c
            FROM Leave_Request__c
            WHERE Id = :req.Id
        ];
        if (updatedRequest.Status__c == 'Approved') {
            deductBalance(req.Id);
        }
    }

    public static void rejectLeave(Id leaveRequestId, Id approverId, String comments) {
        Leave_Request__c req = [
            SELECT Id, Status__c, Manager__c, Approval_Mode_Snapshot__c, Approval_Target_Snapshot__c
            FROM Leave_Request__c
            WHERE Id = :leaveRequestId
        ];

        if (req.Status__c != 'Pending_Manager_Approval' && req.Status__c != 'Pending_HR_Approval') {
            throw new IllegalArgumentException('Leave request is not in a rejectable status');
        }

        String stage = req.Status__c == 'Pending_HR_Approval' ? 'HR_Approval' : 'Manager_Approval';
        req.Status__c = 'Rejected';
        LeaveApprovalHistoryService.suppressTransitionHistory(true);
        try {
            update req;
        } finally {
            LeaveApprovalHistoryService.suppressTransitionHistory(false);
        }

        Leave_Approval_History__c history = LeaveApprovalHistoryService.buildHistory(req, stage, 'Rejected', comments);
        history.Approver__c = approverId;
        insert history;
    }

    public static void deductBalance(Id leaveRequestId) {
        Leave_Request__c req = [
            SELECT Id, Employee__c, Leave_Type__c, Start_Date__c, End_Date__c,
                   Balance_Year__c, Days__c, Balance_Deducted__c
            FROM Leave_Request__c
            WHERE Id = :leaveRequestId
        ];

        if (req.Balance_Deducted__c) {
            return;
        }

        List<LeaveRequestSegmentService.SegmentDetail> segments =
            LeaveRequestSegmentService.buildSegments(req.Start_Date__c, req.End_Date__c, null);
        Set<Integer> balanceYears = new Set<Integer>();
        for (LeaveRequestSegmentService.SegmentDetail segment : segments) {
            balanceYears.add(segment.balanceYear);
        }

        Map<Integer, Leave_Balance__c> balanceByYear = getBalancesByYears(req.Employee__c, balanceYears);
        List<Leave_Balance__c> balancesToUpdate = new List<Leave_Balance__c>();
        Set<Id> updatedBalanceIds = new Set<Id>();

        for (LeaveRequestSegmentService.SegmentDetail segment : segments) {
            Leave_Balance__c bal = balanceByYear.get(segment.balanceYear);
            if (bal == null) {
                throw new IllegalArgumentException(
                    'No leave balance found for employee ' + req.Employee__c + ' in year ' + segment.balanceYear
                );
            }

            if (req.Leave_Type__c == 'Annual') {
                expireCarryoverIfNeeded(bal, segment.segmentStartDate);

                Decimal remainingDays = segment.days == null ? 0 : segment.days;
                Decimal carryoverAvailable = bal.Carryover_Annual_Leave__c == null ? 0 : bal.Carryover_Annual_Leave__c;
                Decimal annualAvailable = bal.Annual_Leave__c == null ? 0 : bal.Annual_Leave__c;

                if (carryoverAvailable + annualAvailable < remainingDays) {
                    throw new IllegalArgumentException(
                        'Insufficient annual leave balance for year ' + String.valueOf(segment.balanceYear)
                    );
                }

                Decimal deductFromCarryover = Math.min(carryoverAvailable, remainingDays);
                bal.Carryover_Annual_Leave__c = carryoverAvailable - deductFromCarryover;
                remainingDays -= deductFromCarryover;
                bal.Annual_Leave__c = annualAvailable - remainingDays;
            } else if (req.Leave_Type__c == 'Sick') {
                bal.Sick_Leave__c -= segment.days;
                if (bal.Sick_Leave__c < 0) {
                    throw new IllegalArgumentException(
                        'Insufficient sick leave balance for year ' + String.valueOf(segment.balanceYear)
                    );
                }
            } else if (req.Leave_Type__c == 'Personal') {
                bal.Personal_Leave__c -= segment.days;
                if (bal.Personal_Leave__c < 0) {
                    throw new IllegalArgumentException(
                        'Insufficient personal leave balance for year ' + String.valueOf(segment.balanceYear)
                    );
                }
            }

            if (!updatedBalanceIds.contains(bal.Id)) {
                balancesToUpdate.add(bal);
                updatedBalanceIds.add(bal.Id);
            }
        }

        if (!balancesToUpdate.isEmpty()) {
            update balancesToUpdate;
        }

        req.Balance_Deducted__c = true;
        update req;
    }

    public static Boolean hasOverlappingDates(Id employeeId, Date startDate, Date endDate, Id excludeRequestId) {
        List<Leave_Request__c> overlaps = [
            SELECT Id FROM Leave_Request__c
            WHERE Employee__c = :employeeId
            AND Start_Date__c <= :endDate
            AND End_Date__c >= :startDate
            AND Id != :excludeRequestId
            AND Status__c IN ('Submitted', 'Pending_Manager_Approval', 'Pending_HR_Approval', 'Approved')
        ];
        return !overlaps.isEmpty();
    }

    public static void validateBalance(
        Id employeeId,
        String leaveType,
        Decimal days,
        Date startDate,
        Date endDate,
        Id excludeRequestId
    ) {
        List<LeaveRequestSegmentService.SegmentDetail> segments =
            LeaveRequestSegmentService.buildSegments(startDate, endDate, null);
        Set<Integer> balanceYears = new Set<Integer>();
        for (LeaveRequestSegmentService.SegmentDetail segment : segments) {
            balanceYears.add(segment.balanceYear);
        }

        Map<Integer, Leave_Balance__c> balanceByYear = getBalancesByYears(employeeId, balanceYears);
        if (balanceByYear.isEmpty()) {
            throw new IllegalArgumentException('No leave balance found. Please contact HR to set up your leave balance.');
        }

        Map<Integer, Decimal> usedDaysByYear = new Map<Integer, Decimal>();
        if (excludeRequestId != null) {
            for (Leave_Request__c existing : [
                SELECT Start_Date__c, End_Date__c
                FROM Leave_Request__c
                WHERE Employee__c = :employeeId AND Leave_Type__c = :leaveType
                AND Id != :excludeRequestId
                AND Status__c IN ('Submitted', 'Pending_Manager_Approval', 'Pending_HR_Approval', 'Approved')
            ]) {
                Map<Integer, Decimal> existingDaysByYear =
                    LeaveRequestSegmentService.summarizeDaysByYear(existing.Start_Date__c, existing.End_Date__c);
                for (Integer yearValue : existingDaysByYear.keySet()) {
                    Decimal existingDays = usedDaysByYear.containsKey(yearValue)
                        ? usedDaysByYear.get(yearValue)
                        : 0;
                    usedDaysByYear.put(yearValue, existingDays + existingDaysByYear.get(yearValue));
                }
            }
        }

        for (LeaveRequestSegmentService.SegmentDetail segment : segments) {
            Leave_Balance__c bal = balanceByYear.get(segment.balanceYear);
            if (bal == null) {
                throw new IllegalArgumentException(
                    'No leave balance found. Please contact HR to set up leave balance for year ' +
                    String.valueOf(segment.balanceYear) + '.'
                );
            }

            expireCarryoverIfNeeded(bal, segment.segmentStartDate);
            Decimal remaining = getRemainingBalance(bal, leaveType);
            Decimal usedDays = usedDaysByYear.containsKey(segment.balanceYear)
                ? usedDaysByYear.get(segment.balanceYear)
                : 0;

            if (remaining - usedDays < segment.days) {
                throw new IllegalArgumentException(
                    'Insufficient ' + leaveType + ' balance for year ' + String.valueOf(segment.balanceYear) +
                    '. Remaining: ' + (remaining - usedDays) + ', Requested: ' + segment.days
                );
            }
        }
    }

    public static void handleApprovalResult(Id leaveRequestId, Boolean isApproved) {
        if (isProcessing) return;
        isProcessing = true;
        try {
            if (isApproved) {
                deductBalance(leaveRequestId);
            }
        } finally {
            isProcessing = false;
        }
    }

    private static Integer resolveBalanceYear(Date startDate, Decimal balanceYearValue) {
        if (balanceYearValue != null) {
            return Integer.valueOf(String.valueOf(balanceYearValue));
        }
        return startDate == null ? System.today().year() : startDate.year();
    }

    private static Leave_Balance__c getBalance(Id employeeId, Integer yearValue) {
        Map<Integer, Leave_Balance__c> balanceByYear = getBalancesByYears(employeeId, new Set<Integer>{ yearValue });
        return balanceByYear.containsKey(yearValue) ? balanceByYear.get(yearValue) : null;
    }

    private static Map<Integer, Leave_Balance__c> getBalancesByYears(Id employeeId, Set<Integer> yearValues) {
        Map<Integer, Leave_Balance__c> balanceByYear = new Map<Integer, Leave_Balance__c>();
        if (employeeId == null || yearValues.isEmpty()) {
            return balanceByYear;
        }

        Set<String> uniqueKeys = new Set<String>();
        for (Integer yearValue : yearValues) {
            uniqueKeys.add(employeeId + '-' + String.valueOf(yearValue));
        }

        for (Leave_Balance__c balance : [
            SELECT Id, Year__c, Annual_Leave__c, Sick_Leave__c, Personal_Leave__c,
                   Carryover_Annual_Leave__c, Carryover_Expiry_Date__c
            FROM Leave_Balance__c
            WHERE Unique_Key__c IN :uniqueKeys
        ]) {
            balanceByYear.put(Integer.valueOf(String.valueOf(balance.Year__c)), balance);
        }
        return balanceByYear;
    }

    private static Decimal getRemainingBalance(Leave_Balance__c bal, String leaveType) {
        if (leaveType == 'Annual') {
            Decimal annualAvailable = bal.Annual_Leave__c == null ? 0 : bal.Annual_Leave__c;
            Decimal carryoverAvailable = bal.Carryover_Annual_Leave__c == null ? 0 : bal.Carryover_Annual_Leave__c;
            return annualAvailable + carryoverAvailable;
        }
        if (leaveType == 'Sick') {
            return bal.Sick_Leave__c == null ? 0 : bal.Sick_Leave__c;
        }
        if (leaveType == 'Personal') {
            return bal.Personal_Leave__c == null ? 0 : bal.Personal_Leave__c;
        }
        return 0;
    }

    private static void expireCarryoverIfNeeded(Leave_Balance__c bal, Date businessDate) {
        if (bal.Carryover_Annual_Leave__c == null || bal.Carryover_Annual_Leave__c <= 0) {
            return;
        }
        if (bal.Carryover_Expiry_Date__c == null) {
            return;
        }
        Date effectiveDate = businessDate == null ? System.today() : businessDate;
        if (effectiveDate > bal.Carryover_Expiry_Date__c) {
            bal.Carryover_Annual_Leave__c = 0;
        }
    }
}
