public without sharing class LeaveRequestSegmentService {

    public class SegmentDetail {
        public Date segmentStartDate;
        public Date segmentEndDate;
        public Integer balanceYear;
        public Decimal days;
        public Id leaveTypeDefinitionId;
    }

    public static List<SegmentDetail> buildSegments(
        Date startDate,
        Date endDate,
        Id leaveTypeDefinitionId
    ) {
        List<SegmentDetail> segments = new List<SegmentDetail>();
        if (startDate == null || endDate == null || endDate < startDate) {
            return segments;
        }

        Date currentStartDate = startDate;
        Integer segmentIndex = 0;
        while (currentStartDate <= endDate && segmentIndex < 20) {
            Date yearEndDate = Date.newInstance(currentStartDate.year(), 12, 31);
            Date currentEndDate = endDate < yearEndDate ? endDate : yearEndDate;

            SegmentDetail segment = new SegmentDetail();
            segment.segmentStartDate = currentStartDate;
            segment.segmentEndDate = currentEndDate;
            segment.balanceYear = currentStartDate.year();
            segment.days = currentStartDate.daysBetween(currentEndDate) + 1;
            segment.leaveTypeDefinitionId = leaveTypeDefinitionId;
            segments.add(segment);

            currentStartDate = currentEndDate.addDays(1);
            segmentIndex++;
        }

        return segments;
    }

    public static Map<Integer, Decimal> summarizeDaysByYear(Date startDate, Date endDate) {
        Map<Integer, Decimal> daysByYear = new Map<Integer, Decimal>();
        for (SegmentDetail segment : buildSegments(startDate, endDate, null)) {
            Decimal existingDays = daysByYear.containsKey(segment.balanceYear)
                ? daysByYear.get(segment.balanceYear)
                : 0;
            daysByYear.put(segment.balanceYear, existingDays + segment.days);
        }
        return daysByYear;
    }

    public static void syncSegments(List<Leave_Request__c> requests) {
        Set<Id> requestIds = new Set<Id>();
        Map<Id, Leave_Request__c> requestById = new Map<Id, Leave_Request__c>();
        for (Leave_Request__c requestRecord : requests) {
            if (requestRecord.Id == null) {
                continue;
            }
            requestIds.add(requestRecord.Id);
            requestById.put(requestRecord.Id, requestRecord);
        }

        if (requestIds.isEmpty()) {
            return;
        }

        List<Leave_Request_Segment__c> existingSegments = [
            SELECT Id
            FROM Leave_Request_Segment__c
            WHERE Leave_Request__c IN :requestIds
        ];
        if (!existingSegments.isEmpty()) {
            delete existingSegments;
        }

        List<Leave_Request_Segment__c> segmentsToInsert = new List<Leave_Request_Segment__c>();
        for (Leave_Request__c requestRecord : requestById.values()) {
            Integer segmentIndex = 1;
            for (SegmentDetail segment : buildSegments(
                requestRecord.Start_Date__c,
                requestRecord.End_Date__c,
                requestRecord.Leave_Type_Definition__c
            )) {
                segmentsToInsert.add(new Leave_Request_Segment__c(
                    Leave_Request__c = requestRecord.Id,
                    Segment_Start_Date__c = segment.segmentStartDate,
                    Segment_End_Date__c = segment.segmentEndDate,
                    Balance_Year__c = segment.balanceYear,
                    Days__c = segment.days,
                    Leave_Type_Definition__c = segment.leaveTypeDefinitionId,
                    Segment_Status__c = resolveSegmentStatus(requestRecord.Status__c),
                    Unique_Key__c = buildUniqueKey(requestRecord.Id, segment.balanceYear, segmentIndex)
                ));
                segmentIndex++;
            }
        }

        if (!segmentsToInsert.isEmpty()) {
            insert segmentsToInsert;
        }
    }

    private static String resolveSegmentStatus(String requestStatus) {
        if (requestStatus == 'Approved') {
            return 'Consumed';
        }
        if (requestStatus == 'Rejected' || requestStatus == 'Cancelled') {
            return 'Released';
        }
        if (requestStatus == 'Submitted' ||
            requestStatus == 'Pending_Manager_Approval' ||
            requestStatus == 'Pending_HR_Approval') {
            return 'Reserved';
        }
        return 'Draft';
    }

    private static String buildUniqueKey(Id requestId, Integer balanceYear, Integer segmentIndex) {
        return String.valueOf(requestId) + '-' + String.valueOf(balanceYear) + '-' + String.valueOf(segmentIndex);
    }
}
