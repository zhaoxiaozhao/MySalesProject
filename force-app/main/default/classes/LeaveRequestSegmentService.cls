public without sharing class LeaveRequestSegmentService {

    public static final String FULL_DAY_TIME_SLOT = 'Full_Day';
    public static final String MORNING_TIME_SLOT = 'Morning';
    public static final String AFTERNOON_TIME_SLOT = 'Afternoon';
    private static final Set<String> SUPPORTED_TIME_SLOTS = new Set<String>{
        FULL_DAY_TIME_SLOT,
        MORNING_TIME_SLOT,
        AFTERNOON_TIME_SLOT
    };
    private static final Date HALF_DAY_EPOCH = Date.newInstance(2000, 1, 1);

    public class SegmentDetail {
        public Date segmentStartDate;
        public Date segmentEndDate;
        public Integer balanceYear;
        public Decimal days;
        public Id leaveTypeDefinitionId;
        public String startTimeSlot;
        public String endTimeSlot;
    }

    public static List<SegmentDetail> buildSegments(
        Date startDate,
        Date endDate,
        Id leaveTypeDefinitionId
    ) {
        return buildSegments(startDate, endDate, leaveTypeDefinitionId, null, null);
    }

    public static List<SegmentDetail> buildSegments(
        Date startDate,
        Date endDate,
        Id leaveTypeDefinitionId,
        String startTimeSlot,
        String endTimeSlot
    ) {
        List<SegmentDetail> segments = new List<SegmentDetail>();
        if (startDate == null || endDate == null || endDate < startDate) {
            return segments;
        }

        String normalizedStartTimeSlot = normalizeTimeSlot(startTimeSlot);
        String normalizedEndTimeSlot = normalizeTimeSlot(endTimeSlot);
        calculateDays(startDate, endDate, normalizedStartTimeSlot, normalizedEndTimeSlot);

        Date currentStartDate = startDate;
        Integer segmentIndex = 0;
        while (currentStartDate <= endDate && segmentIndex < 20) {
            Date yearEndDate = Date.newInstance(currentStartDate.year(), 12, 31);
            Date currentEndDate = endDate < yearEndDate ? endDate : yearEndDate;

            SegmentDetail segment = new SegmentDetail();
            segment.segmentStartDate = currentStartDate;
            segment.segmentEndDate = currentEndDate;
            segment.balanceYear = currentStartDate.year();
            segment.leaveTypeDefinitionId = leaveTypeDefinitionId;
            segment.startTimeSlot = currentStartDate == startDate
                ? normalizedStartTimeSlot
                : FULL_DAY_TIME_SLOT;
            segment.endTimeSlot = currentEndDate == endDate
                ? normalizedEndTimeSlot
                : FULL_DAY_TIME_SLOT;
            segment.days = calculateDays(
                segment.segmentStartDate,
                segment.segmentEndDate,
                segment.startTimeSlot,
                segment.endTimeSlot
            );
            segments.add(segment);

            currentStartDate = currentEndDate.addDays(1);
            segmentIndex++;
        }

        return segments;
    }

    public static Map<Integer, Decimal> summarizeDaysByYear(Date startDate, Date endDate) {
        return summarizeDaysByYear(startDate, endDate, null, null);
    }

    public static Map<Integer, Decimal> summarizeDaysByYear(
        Date startDate,
        Date endDate,
        String startTimeSlot,
        String endTimeSlot
    ) {
        Map<Integer, Decimal> daysByYear = new Map<Integer, Decimal>();
        for (SegmentDetail segment : buildSegments(startDate, endDate, null, startTimeSlot, endTimeSlot)) {
            Decimal existingDays = daysByYear.containsKey(segment.balanceYear)
                ? daysByYear.get(segment.balanceYear)
                : 0;
            daysByYear.put(segment.balanceYear, existingDays + segment.days);
        }
        return daysByYear;
    }

    public static Decimal calculateDays(
        Date startDate,
        Date endDate,
        String startTimeSlot,
        String endTimeSlot
    ) {
        if (startDate == null || endDate == null || endDate < startDate) {
            return 0;
        }

        Integer startIndex = buildHalfDayStartIndex(startDate, normalizeTimeSlot(startTimeSlot));
        Integer endExclusiveIndex = buildHalfDayEndExclusiveIndex(endDate, normalizeTimeSlot(endTimeSlot));
        Integer halfDayUnits = endExclusiveIndex - startIndex;
        if (halfDayUnits <= 0) {
            throw new IllegalArgumentException(
                'The selected leave time slots are invalid for the chosen date range.'
            );
        }
        return Decimal.valueOf(halfDayUnits) / 2;
    }

    public static Boolean hasOverlappingRange(
        Date startDate,
        Date endDate,
        String startTimeSlot,
        String endTimeSlot,
        Date existingStartDate,
        Date existingEndDate,
        String existingStartTimeSlot,
        String existingEndTimeSlot
    ) {
        if (startDate == null || endDate == null || existingStartDate == null || existingEndDate == null) {
            return false;
        }

        Integer requestStartIndex = buildHalfDayStartIndex(startDate, normalizeTimeSlot(startTimeSlot));
        Integer requestEndExclusiveIndex =
            buildHalfDayEndExclusiveIndex(endDate, normalizeTimeSlot(endTimeSlot));
        Integer existingStartIndex =
            buildHalfDayStartIndex(existingStartDate, normalizeTimeSlot(existingStartTimeSlot));
        Integer existingEndExclusiveIndex =
            buildHalfDayEndExclusiveIndex(existingEndDate, normalizeTimeSlot(existingEndTimeSlot));

        return requestStartIndex < existingEndExclusiveIndex
            && existingStartIndex < requestEndExclusiveIndex;
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
                requestRecord.Leave_Type_Definition__c,
                (String)requestRecord.get('Start_Time_Slot__c'),
                (String)requestRecord.get('End_Time_Slot__c')
            )) {
                segmentsToInsert.add(new Leave_Request_Segment__c(
                    Leave_Request__c = requestRecord.Id,
                    Segment_Start_Date__c = segment.segmentStartDate,
                    Segment_End_Date__c = segment.segmentEndDate,
                    Segment_Start_Time_Slot__c = segment.startTimeSlot,
                    Segment_End_Time_Slot__c = segment.endTimeSlot,
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

    private static String normalizeTimeSlot(String timeSlot) {
        if (String.isBlank(timeSlot)) {
            return FULL_DAY_TIME_SLOT;
        }
        if (!SUPPORTED_TIME_SLOTS.contains(timeSlot)) {
            throw new IllegalArgumentException('Please select a valid leave time slot.');
        }
        return timeSlot;
    }

    private static Integer buildHalfDayStartIndex(Date dateValue, String normalizedTimeSlot) {
        return HALF_DAY_EPOCH.daysBetween(dateValue) * 2 +
            (normalizedTimeSlot == AFTERNOON_TIME_SLOT ? 1 : 0);
    }

    private static Integer buildHalfDayEndExclusiveIndex(Date dateValue, String normalizedTimeSlot) {
        return HALF_DAY_EPOCH.daysBetween(dateValue) * 2 +
            (normalizedTimeSlot == MORNING_TIME_SLOT ? 1 : 2);
    }
}
