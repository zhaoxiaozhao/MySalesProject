public without sharing class LeaveBalanceLedgerService {

    public class BalanceSummary {
        @AuraEnabled public String name;
        @AuraEnabled public Id balanceId;
        @AuraEnabled public Id userId;
        @AuraEnabled public String userName;
        @AuraEnabled public Decimal yearValue;
        @AuraEnabled public Decimal annualTotalAvailable;
        @AuraEnabled public Decimal carryoverAnnualLeave;
        @AuraEnabled public Date carryoverExpiryDate;
        @AuraEnabled public Decimal sickLeave;
        @AuraEnabled public Decimal personalLeave;
    }

    private class RequestContext {
        Leave_Request__c requestRecord;
        List<Leave_Request_Segment__c> segments = new List<Leave_Request_Segment__c>();
        Map<Integer, Leave_Balance_Line__c> lineByYear = new Map<Integer, Leave_Balance_Line__c>();
        LeaveTypePolicyService.LeaveTypePolicy policy;
    }

    public static void validateBalance(
        Id employeeId,
        Id leaveTypeDefinitionId,
        String leaveTypeCode,
        Date startDate,
        Date endDate,
        Id excludeRequestId
    ) {
        List<LeaveRequestSegmentService.SegmentDetail> segments =
            LeaveRequestSegmentService.buildSegments(startDate, endDate, leaveTypeDefinitionId);
        if (segments.isEmpty()) {
            return;
        }

        Map<Integer, Leave_Balance__c> balanceByYear = ensureBalanceHeads(
            employeeId,
            collectBalanceYears(segments),
            false
        );
        for (LeaveRequestSegmentService.SegmentDetail segment : segments) {
            if (!balanceByYear.containsKey(segment.balanceYear)) {
                throw new IllegalArgumentException(buildMissingBalanceMessage(segment.balanceYear));
            }
        }

        RequestContext context = new RequestContext();
        context.policy = resolvePolicy(leaveTypeDefinitionId, leaveTypeCode);
        context.lineByYear = ensureLinesForYears(
            employeeId,
            collectBalanceYears(segments),
            context.policy,
            false
        );
        Map<Integer, Decimal> reservedDaysByYear = summarizeExistingActiveUsage(
            employeeId,
            context.policy.typeCode,
            excludeRequestId
        );

        for (LeaveRequestSegmentService.SegmentDetail segment : segments) {
            Leave_Balance_Line__c lineRecord = context.lineByYear.get(segment.balanceYear);
            if (lineRecord == null) {
                throw new IllegalArgumentException(buildMissingBalanceMessage(segment.balanceYear));
            }

            Decimal available = calculateEffectiveAvailable(lineRecord, context.policy, segment.segmentStartDate);
            Decimal activeUsage = reservedDaysByYear.containsKey(segment.balanceYear)
                ? reservedDaysByYear.get(segment.balanceYear)
                : 0;
            if (available - activeUsage < segment.days) {
                throw new IllegalArgumentException(
                    'Insufficient ' + context.policy.typeCode + ' balance for year ' +
                    String.valueOf(segment.balanceYear) + '. Remaining: ' + (available - activeUsage) +
                    ', Requested: ' + segment.days
                );
            }
        }
    }

    public static void reserveBalance(Id leaveRequestId) {
        RequestContext context = loadRequestContext(leaveRequestId);
        if (context.segments.isEmpty()) {
            return;
        }

        List<Leave_Balance_Line__c> linesToUpdate = new List<Leave_Balance_Line__c>();
        List<Leave_Request_Segment__c> segmentsToUpdate = new List<Leave_Request_Segment__c>();
        List<Leave_Balance_Transaction__c> transactionsToInsert = new List<Leave_Balance_Transaction__c>();
        Set<Id> touchedBalanceIds = new Set<Id>();

        for (Leave_Request_Segment__c segmentRecord : context.segments) {
            if (segmentRecord.Segment_Status__c == 'Reserved' || segmentRecord.Segment_Status__c == 'Consumed') {
                continue;
            }

            Leave_Balance_Line__c lineRecord =
                context.lineByYear.get(Integer.valueOf(String.valueOf(segmentRecord.Balance_Year__c)));
            if (lineRecord == null) {
                throw new IllegalArgumentException(
                    buildMissingBalanceMessage(Integer.valueOf(String.valueOf(segmentRecord.Balance_Year__c)))
                );
            }

            Decimal available = calculateEffectiveAvailable(
                lineRecord,
                context.policy,
                segmentRecord.Segment_Start_Date__c
            );
            if (available < segmentRecord.Days__c) {
                throw new IllegalArgumentException(
                    'Insufficient ' + context.policy.typeCode + ' balance for year ' +
                    String.valueOf(segmentRecord.Balance_Year__c) + '. Remaining: ' + available +
                    ', Requested: ' + segmentRecord.Days__c
                );
            }

            lineRecord.Reserved__c = safeDecimal(lineRecord.Reserved__c) + safeDecimal(segmentRecord.Days__c);
            segmentRecord.Segment_Status__c = 'Reserved';
            transactionsToInsert.add(buildTransaction(
                lineRecord.Id,
                leaveRequestId,
                'Reserve',
                segmentRecord.Days__c,
                segmentRecord.Segment_Start_Date__c,
                buildIdempotencyKey('RESERVE', leaveRequestId, segmentRecord.Unique_Key__c),
                'Reserved from leave request segment ' + segmentRecord.Unique_Key__c,
                context.policy.policyVersion
            ));
            linesToUpdate.add(lineRecord);
            segmentsToUpdate.add(segmentRecord);
            touchedBalanceIds.add(lineRecord.Leave_Balance__c);
        }

        persistLedgerChanges(linesToUpdate, segmentsToUpdate, transactionsToInsert, touchedBalanceIds);
    }

    public static void consumeReservedBalance(Id leaveRequestId) {
        RequestContext context = loadRequestContext(leaveRequestId);
        if (context.segments.isEmpty()) {
            return;
        }

        List<Leave_Balance_Line__c> linesToUpdate = new List<Leave_Balance_Line__c>();
        List<Leave_Request_Segment__c> segmentsToUpdate = new List<Leave_Request_Segment__c>();
        List<Leave_Balance_Transaction__c> transactionsToInsert = new List<Leave_Balance_Transaction__c>();
        Set<Id> touchedBalanceIds = new Set<Id>();

        for (Leave_Request_Segment__c segmentRecord : context.segments) {
            Boolean isLegacyApprovedConsumption =
                context.requestRecord.Status__c == 'Approved' &&
                context.requestRecord.Balance_Deducted__c == false;
            if (segmentRecord.Segment_Status__c == 'Consumed' && !isLegacyApprovedConsumption) {
                continue;
            }
            if (segmentRecord.Segment_Status__c != 'Reserved' && !isLegacyApprovedConsumption) {
                throw new IllegalArgumentException(
                    'Leave request segment ' + segmentRecord.Unique_Key__c + ' is not reserved yet.'
                );
            }

            Leave_Balance_Line__c lineRecord =
                context.lineByYear.get(Integer.valueOf(String.valueOf(segmentRecord.Balance_Year__c)));
            if (lineRecord == null) {
                throw new IllegalArgumentException(
                    buildMissingBalanceMessage(Integer.valueOf(String.valueOf(segmentRecord.Balance_Year__c)))
                );
            }

            Decimal reservedQuantity = safeDecimal(lineRecord.Reserved__c);
            if (reservedQuantity < safeDecimal(segmentRecord.Days__c) && isLegacyApprovedConsumption) {
                Decimal available = calculateEffectiveAvailable(
                    lineRecord,
                    context.policy,
                    segmentRecord.Segment_Start_Date__c
                );
                if (available < safeDecimal(segmentRecord.Days__c)) {
                    throw new IllegalArgumentException(
                        'Insufficient ' + context.policy.typeCode + ' balance for year ' +
                        String.valueOf(segmentRecord.Balance_Year__c) + '. Remaining: ' + available +
                        ', Requested: ' + segmentRecord.Days__c
                    );
                }
            }
            lineRecord.Reserved__c = Math.max(0, reservedQuantity - safeDecimal(segmentRecord.Days__c));
            lineRecord.Used__c = safeDecimal(lineRecord.Used__c) + safeDecimal(segmentRecord.Days__c);
            segmentRecord.Segment_Status__c = 'Consumed';
            transactionsToInsert.add(buildTransaction(
                lineRecord.Id,
                leaveRequestId,
                'Consume',
                segmentRecord.Days__c,
                segmentRecord.Segment_Start_Date__c,
                buildIdempotencyKey('CONSUME', leaveRequestId, segmentRecord.Unique_Key__c),
                'Consumed from leave request segment ' + segmentRecord.Unique_Key__c,
                context.policy.policyVersion
            ));
            linesToUpdate.add(lineRecord);
            segmentsToUpdate.add(segmentRecord);
            touchedBalanceIds.add(lineRecord.Leave_Balance__c);
        }

        persistLedgerChanges(linesToUpdate, segmentsToUpdate, transactionsToInsert, touchedBalanceIds);
        update new Leave_Request__c(
            Id = leaveRequestId,
            Balance_Deducted__c = true
        );
    }

    public static void releaseReservedBalance(Id leaveRequestId, String comments) {
        RequestContext context = loadRequestContext(leaveRequestId);
        if (context.segments.isEmpty()) {
            return;
        }

        List<Leave_Balance_Line__c> linesToUpdate = new List<Leave_Balance_Line__c>();
        List<Leave_Request_Segment__c> segmentsToUpdate = new List<Leave_Request_Segment__c>();
        List<Leave_Balance_Transaction__c> transactionsToInsert = new List<Leave_Balance_Transaction__c>();
        Set<Id> touchedBalanceIds = new Set<Id>();

        for (Leave_Request_Segment__c segmentRecord : context.segments) {
            if (segmentRecord.Segment_Status__c != 'Reserved') {
                continue;
            }

            Leave_Balance_Line__c lineRecord =
                context.lineByYear.get(Integer.valueOf(String.valueOf(segmentRecord.Balance_Year__c)));
            if (lineRecord == null) {
                continue;
            }

            lineRecord.Reserved__c = Math.max(
                0,
                safeDecimal(lineRecord.Reserved__c) - safeDecimal(segmentRecord.Days__c)
            );
            segmentRecord.Segment_Status__c = 'Released';
            transactionsToInsert.add(buildTransaction(
                lineRecord.Id,
                leaveRequestId,
                'Release',
                segmentRecord.Days__c,
                segmentRecord.Segment_Start_Date__c,
                buildIdempotencyKey('RELEASE', leaveRequestId, segmentRecord.Unique_Key__c),
                String.isBlank(comments)
                    ? 'Released from leave request segment ' + segmentRecord.Unique_Key__c
                    : comments,
                context.policy.policyVersion
            ));
            linesToUpdate.add(lineRecord);
            segmentsToUpdate.add(segmentRecord);
            touchedBalanceIds.add(lineRecord.Leave_Balance__c);
        }

        persistLedgerChanges(linesToUpdate, segmentsToUpdate, transactionsToInsert, touchedBalanceIds);
        update new Leave_Request__c(
            Id = leaveRequestId,
            Balance_Deducted__c = false
        );
    }

    public static void carryForwardAnnualLeave(
        Integer sourceYear,
        Integer targetYear,
        Decimal carryoverLimit,
        Integer expiryMonth,
        Integer expiryDay
    ) {
        LeaveTypePolicyService.LeaveTypePolicy policy =
            LeaveTypePolicyService.getPolicyByTypeCode('ANNUAL');
        if (policy == null || policy.allowCarryover == false) {
            return;
        }

        Decimal effectiveLimit = policy.carryoverLimit == null ? carryoverLimit : policy.carryoverLimit;
        Integer effectiveExpiryMonth = policy.carryoverExpireMonth == null ? expiryMonth : policy.carryoverExpireMonth;
        Integer effectiveExpiryDay = policy.carryoverExpireDay == null ? expiryDay : policy.carryoverExpireDay;

        List<Leave_Balance__c> sourceBalances = [
            SELECT Id, User__c, Year__c, Balance_Year__c, Unique_Key__c,
                   Annual_Leave__c, Carryover_Annual_Leave__c
            FROM Leave_Balance__c
            WHERE Year__c = :sourceYear
            AND User__c != null
        ];
        if (sourceBalances.isEmpty()) {
            return;
        }

        if (policy.definitionId == null) {
            carryForwardLegacyAnnualLeave(
                sourceBalances,
                sourceYear,
                targetYear,
                effectiveLimit,
                effectiveExpiryMonth,
                effectiveExpiryDay
            );
            return;
        }

        List<Leave_Balance_Line__c> linesToUpdate = new List<Leave_Balance_Line__c>();
        List<Leave_Balance_Transaction__c> transactionsToInsert = new List<Leave_Balance_Transaction__c>();
        Set<Id> touchedBalanceIds = new Set<Id>();
        Set<String> existingIdempotencyKeys = queryExistingTransactionKeys(
            new Set<String>(),
            'CARRYOVER-' + sourceYear + '-' + targetYear
        );

        for (Leave_Balance__c sourceBalance : sourceBalances) {
            Leave_Balance_Line__c sourceLine = ensureLinesForYears(
                sourceBalance.User__c,
                new Set<Integer>{ sourceYear },
                policy,
                false
            ).get(sourceYear);
            if (sourceLine == null) {
                continue;
            }

            String carryoverKey = 'CARRYOVER-' + sourceYear + '-' + targetYear + '-' + sourceBalance.User__c;
            if (existingIdempotencyKeys.contains(carryoverKey)) {
                continue;
            }

            Leave_Balance_Line__c targetLine = ensureLinesForYears(
                sourceBalance.User__c,
                new Set<Integer>{ targetYear },
                policy,
                true
            ).get(targetYear);
            if (targetLine == null) {
                continue;
            }

            Decimal sourceAvailable = calculateEffectiveAvailable(
                sourceLine,
                policy,
                Date.newInstance(sourceYear, 12, 31)
            );
            Decimal carryoverAmount = Math.min(Math.max(sourceAvailable, 0), effectiveLimit);
            if (carryoverAmount <= 0) {
                existingIdempotencyKeys.add(carryoverKey);
                continue;
            }

            targetLine.Carried_Forward__c = safeDecimal(targetLine.Carried_Forward__c) + carryoverAmount;
            linesToUpdate.add(targetLine);
            transactionsToInsert.add(buildTransaction(
                targetLine.Id,
                null,
                'Carryover',
                carryoverAmount,
                buildExpiryDate(targetYear, effectiveExpiryMonth, effectiveExpiryDay),
                carryoverKey,
                'Annual leave carryover from ' + sourceYear,
                policy.policyVersion
            ));
            touchedBalanceIds.add(targetLine.Leave_Balance__c);
        }

        persistLedgerChanges(linesToUpdate, null, transactionsToInsert, touchedBalanceIds);
        if (!touchedBalanceIds.isEmpty()) {
            applyCarryoverHeadMetadata(
                touchedBalanceIds,
                sourceYear,
                targetYear,
                effectiveExpiryMonth,
                effectiveExpiryDay
            );
        }
    }

    public static Integer expireCarryover(Date asOfDate) {
        Date effectiveDate = asOfDate == null ? System.today() : asOfDate;
        LeaveTypePolicyService.LeaveTypePolicy policy =
            LeaveTypePolicyService.getPolicyByTypeCode('ANNUAL');
        if (policy == null) {
            return 0;
        }

        if (policy.definitionId == null) {
            return expireLegacyCarryover(effectiveDate);
        }

        for (Leave_Balance__c legacyBalance : [
            SELECT User__c, Year__c
            FROM Leave_Balance__c
            WHERE Carryover_Annual_Leave__c > 0
            AND User__c != null
        ]) {
            ensureLinesForYears(
                legacyBalance.User__c,
                new Set<Integer>{ Integer.valueOf(String.valueOf(legacyBalance.Year__c)) },
                policy,
                false
            );
        }

        List<Leave_Balance_Line__c> annualLines = [
            SELECT Id, Leave_Balance__c, Leave_Balance__r.Balance_Year__c, Leave_Balance__r.Year__c,
                   Carried_Forward__c, Expired__c
            FROM Leave_Balance_Line__c
            WHERE Leave_Type_Definition__c = :policy.definitionId
            AND Carried_Forward__c > 0
        ];

        List<Leave_Balance_Line__c> linesToUpdate = new List<Leave_Balance_Line__c>();
        List<Leave_Balance_Transaction__c> transactionsToInsert = new List<Leave_Balance_Transaction__c>();
        Set<Id> touchedBalanceIds = new Set<Id>();

        for (Leave_Balance_Line__c lineRecord : annualLines) {
            Integer yearValue = resolveBalanceYear(
                lineRecord.Leave_Balance__r.Balance_Year__c,
                lineRecord.Leave_Balance__r.Year__c
            );
            Date expiryDate = resolveCarryoverExpiryDate(policy, yearValue);
            if (expiryDate == null || effectiveDate <= expiryDate) {
                continue;
            }
            if (safeDecimal(lineRecord.Carried_Forward__c) <= 0) {
                continue;
            }

            Decimal expiredQuantity = safeDecimal(lineRecord.Carried_Forward__c);
            lineRecord.Expired__c = safeDecimal(lineRecord.Expired__c) + expiredQuantity;
            lineRecord.Carried_Forward__c = 0;
            linesToUpdate.add(lineRecord);
            transactionsToInsert.add(buildTransaction(
                lineRecord.Id,
                null,
                'Expire',
                expiredQuantity,
                effectiveDate,
                'EXPIRE-' + String.valueOf(lineRecord.Id) + '-' + effectiveDate.format(),
                'Expired carryover balance',
                policy.policyVersion
            ));
            touchedBalanceIds.add(lineRecord.Leave_Balance__c);
        }

        persistLedgerChanges(linesToUpdate, null, transactionsToInsert, touchedBalanceIds);
        return linesToUpdate.size();
    }

    public static BalanceSummary getUserBalanceSummary(Id userId, Integer yearValue) {
        List<BalanceSummary> summaries = getBalanceSummariesForUsers(new Set<Id>{ userId }, yearValue);
        return summaries.isEmpty() ? null : summaries[0];
    }

    public static List<BalanceSummary> getBalanceSummariesForUsers(Set<Id> userIds, Integer yearValue) {
        List<BalanceSummary> results = new List<BalanceSummary>();
        if (userIds == null || userIds.isEmpty()) {
            return results;
        }

        List<Leave_Balance__c> balances = [
            SELECT Id, Name, User__c, User__r.Name, Year__c, Balance_Year__c
            FROM Leave_Balance__c
            WHERE User__c IN :userIds
            AND Year__c = :yearValue
            ORDER BY User__r.Name, Year__c DESC
        ];
        return buildSummaries(balances);
    }

    public static List<BalanceSummary> getAllBalanceSummaries(Integer limitSize) {
        Integer safeLimit = limitSize == null || limitSize <= 0 ? 200 : limitSize;
        List<Leave_Balance__c> balances = [
            SELECT Id, Name, User__c, User__r.Name, Year__c, Balance_Year__c
            FROM Leave_Balance__c
            ORDER BY Year__c DESC, User__r.Name
            LIMIT :safeLimit
        ];
        return buildSummaries(balances);
    }

    public static void syncLegacyBalanceHeads(Set<Id> balanceIds) {
        if (balanceIds == null || balanceIds.isEmpty()) {
            return;
        }

        List<Leave_Balance__c> balancesToUpdate = [
            SELECT Id, Year__c, Balance_Year__c, Annual_Leave__c, Carryover_Annual_Leave__c,
                   Carryover_Expiry_Date__c, Sick_Leave__c, Personal_Leave__c
            FROM Leave_Balance__c
            WHERE Id IN :balanceIds
        ];
        if (balancesToUpdate.isEmpty()) {
            return;
        }

        Map<Id, List<Leave_Balance_Line__c>> linesByBalanceId = new Map<Id, List<Leave_Balance_Line__c>>();
        for (Leave_Balance_Line__c lineRecord : [
            SELECT Id, Leave_Balance__c, Available__c, Carried_Forward__c, Reserved__c, Used__c, Expired__c,
                   Leave_Balance__r.Year__c, Leave_Balance__r.Balance_Year__c,
                   Leave_Type_Definition__r.Type_Code__c, Leave_Type_Definition__r.Carryover_Expire_Month__c,
                   Leave_Type_Definition__r.Carryover_Expire_Day__c, Leave_Type_Definition__r.Allow_Carryover__c
            FROM Leave_Balance_Line__c
            WHERE Leave_Balance__c IN :balanceIds
        ]) {
            if (!linesByBalanceId.containsKey(lineRecord.Leave_Balance__c)) {
                linesByBalanceId.put(lineRecord.Leave_Balance__c, new List<Leave_Balance_Line__c>());
            }
            linesByBalanceId.get(lineRecord.Leave_Balance__c).add(lineRecord);
        }

        for (Leave_Balance__c balanceRecord : balancesToUpdate) {
            Decimal annualAvailable = safeDecimal(balanceRecord.Annual_Leave__c);
            Decimal annualCarryover = safeDecimal(balanceRecord.Carryover_Annual_Leave__c);
            Date annualExpiryDate = balanceRecord.Carryover_Expiry_Date__c;
            Decimal sickAvailable = safeDecimal(balanceRecord.Sick_Leave__c);
            Decimal personalAvailable = safeDecimal(balanceRecord.Personal_Leave__c);
            List<Leave_Balance_Line__c> balanceLines = linesByBalanceId.containsKey(balanceRecord.Id)
                ? linesByBalanceId.get(balanceRecord.Id)
                : new List<Leave_Balance_Line__c>();

            for (Leave_Balance_Line__c lineRecord : balanceLines) {
                String typeCode = lineRecord.Leave_Type_Definition__r == null
                    ? null
                    : lineRecord.Leave_Type_Definition__r.Type_Code__c;
                if (typeCode == 'ANNUAL') {
                    LeaveTypePolicyService.LeaveTypePolicy annualPolicy =
                        LeaveTypePolicyService.getPolicyByTypeCode('ANNUAL');
                    annualCarryover = resolveCarryoverAvailable(
                        lineRecord,
                        annualPolicy,
                        System.today()
                    );
                    annualAvailable = Math.max(safeDecimal(lineRecord.Available__c) - annualCarryover, 0);
                    annualExpiryDate = resolveCarryoverExpiryDate(
                        annualPolicy,
                        resolveBalanceYear(balanceRecord.Balance_Year__c, balanceRecord.Year__c)
                    );
                } else if (typeCode == 'SICK') {
                    sickAvailable = safeDecimal(lineRecord.Available__c);
                } else if (typeCode == 'PERSONAL') {
                    personalAvailable = safeDecimal(lineRecord.Available__c);
                }
            }

            balanceRecord.Annual_Leave__c = annualAvailable;
            balanceRecord.Carryover_Annual_Leave__c = annualCarryover;
            balanceRecord.Carryover_Expiry_Date__c = annualExpiryDate;
            balanceRecord.Sick_Leave__c = sickAvailable;
            balanceRecord.Personal_Leave__c = personalAvailable;
        }
        update balancesToUpdate;
    }

    public static void initializeLinesFromBalanceHeads(Set<Id> balanceIds) {
        if (balanceIds == null || balanceIds.isEmpty()) {
            return;
        }

        List<Leave_Balance__c> balanceHeads = [
            SELECT Id, User__c, Year__c, Balance_Year__c, Annual_Leave__c, Carryover_Annual_Leave__c,
                   Sick_Leave__c, Personal_Leave__c
            FROM Leave_Balance__c
            WHERE Id IN :balanceIds
            AND User__c != null
        ];
        if (balanceHeads.isEmpty()) {
            return;
        }

        Map<String, LeaveTypePolicyService.LeaveTypePolicy> policyByTypeCode =
            LeaveTypePolicyService.getPoliciesByTypeCodes(new Set<String>{ 'ANNUAL', 'SICK', 'PERSONAL' });
        Set<String> lineKeys = new Set<String>();
        for (Leave_Balance__c balanceHead : balanceHeads) {
            Integer yearValue = resolveBalanceYear(balanceHead.Balance_Year__c, balanceHead.Year__c);
            for (String typeCode : policyByTypeCode.keySet()) {
                LeaveTypePolicyService.LeaveTypePolicy policy = policyByTypeCode.get(typeCode);
                if (policy == null || policy.definitionId == null) {
                    continue;
                }
                lineKeys.add(buildLineKey(balanceHead.User__c, yearValue, typeCode));
            }
        }

        Map<String, Leave_Balance_Line__c> existingByKey = new Map<String, Leave_Balance_Line__c>();
        if (!lineKeys.isEmpty()) {
            for (Leave_Balance_Line__c lineRecord : [
                SELECT Id, Unique_Key__c
                FROM Leave_Balance_Line__c
                WHERE Unique_Key__c IN :lineKeys
            ]) {
                existingByKey.put(lineRecord.Unique_Key__c, lineRecord);
            }
        }

        List<Leave_Balance_Line__c> linesToUpsert = new List<Leave_Balance_Line__c>();
        for (Leave_Balance__c balanceHead : balanceHeads) {
            Integer yearValue = resolveBalanceYear(balanceHead.Balance_Year__c, balanceHead.Year__c);
            for (String typeCode : policyByTypeCode.keySet()) {
                LeaveTypePolicyService.LeaveTypePolicy policy = policyByTypeCode.get(typeCode);
                if (policy == null || policy.definitionId == null) {
                    continue;
                }

                String lineKey = buildLineKey(balanceHead.User__c, yearValue, typeCode);
                if (existingByKey.containsKey(lineKey)) {
                    continue;
                }
                linesToUpsert.add(buildLineFromLegacyHead(balanceHead, policy, yearValue));
            }
        }

        if (!linesToUpsert.isEmpty()) {
            upsert linesToUpsert Leave_Balance_Line__c.Fields.Unique_Key__c;
            syncLegacyBalanceHeads(balanceIds);
        }
    }

    public static void initializePolicyLines(
        Map<Id, Leave_Balance__c> balanceByUserId,
        Integer yearValue,
        Map<String, Decimal> quotaByTypeCode,
        Boolean overwriteExistingBalances
    ) {
        if (balanceByUserId == null || balanceByUserId.isEmpty()) {
            return;
        }

        List<Leave_Type_Definition__c> definitions = [
            SELECT Id, Name, Type_Code__c, Is_Active__c, Policy_Version__c
            FROM Leave_Type_Definition__c
            WHERE Is_Active__c = true
        ];
        if (definitions.isEmpty()) {
            return;
        }

        Set<String> lineKeys = new Set<String>();
        for (Id userId : balanceByUserId.keySet()) {
            for (Leave_Type_Definition__c definitionRecord : definitions) {
                lineKeys.add(buildLineKey(userId, yearValue, definitionRecord.Type_Code__c));
            }
        }

        Map<String, Leave_Balance_Line__c> existingByKey = new Map<String, Leave_Balance_Line__c>();
        for (Leave_Balance_Line__c lineRecord : [
            SELECT Id, Unique_Key__c, Leave_Balance__c, Granted__c, Granted_By_Policy__c,
                   Opening_Balance__c, Carried_Forward__c, Reserved__c, Used__c, Adjusted__c, Expired__c
            FROM Leave_Balance_Line__c
            WHERE Unique_Key__c IN :lineKeys
        ]) {
            existingByKey.put(lineRecord.Unique_Key__c, lineRecord);
        }

        List<Leave_Balance_Line__c> linesToUpsert = new List<Leave_Balance_Line__c>();
        List<Leave_Balance_Transaction__c> transactionsToInsert = new List<Leave_Balance_Transaction__c>();
        Set<Id> touchedBalanceIds = new Set<Id>();

        for (Id userId : balanceByUserId.keySet()) {
            Leave_Balance__c balanceRecord = balanceByUserId.get(userId);
            for (Leave_Type_Definition__c definitionRecord : definitions) {
                String lineKey = buildLineKey(userId, yearValue, definitionRecord.Type_Code__c);
                Decimal grantedQuantity = quotaByTypeCode.containsKey(definitionRecord.Type_Code__c)
                    ? quotaByTypeCode.get(definitionRecord.Type_Code__c)
                    : 0;
                Leave_Balance_Line__c lineRecord = existingByKey.get(lineKey);
                Boolean isInsert = lineRecord == null;
                if (lineRecord == null) {
                    lineRecord = new Leave_Balance_Line__c(
                        Leave_Balance__c = balanceRecord.Id,
                        Leave_Type_Definition__c = definitionRecord.Id,
                        Unique_Key__c = lineKey,
                        Opening_Balance__c = 0,
                        Granted__c = 0,
                        Granted_By_Policy__c = 0,
                        Carried_Forward__c = 0,
                        Reserved__c = 0,
                        Used__c = 0,
                        Adjusted__c = 0,
                        Expired__c = 0
                    );
                }

                if (isInsert || overwriteExistingBalances) {
                    if (isInsert) {
                        lineRecord.Leave_Balance__c = balanceRecord.Id;
                        lineRecord.Leave_Type_Definition__c = definitionRecord.Id;
                    }
                    lineRecord.Opening_Balance__c = 0;
                    lineRecord.Granted__c = 0;
                    lineRecord.Granted_By_Policy__c = grantedQuantity;
                    if (overwriteExistingBalances) {
                        lineRecord.Carried_Forward__c = 0;
                        lineRecord.Reserved__c = 0;
                        lineRecord.Used__c = 0;
                        lineRecord.Adjusted__c = 0;
                        lineRecord.Expired__c = 0;
                    }
                    linesToUpsert.add(lineRecord);
                }
            }
            touchedBalanceIds.add(balanceRecord.Id);
        }

        if (!linesToUpsert.isEmpty()) {
            upsert linesToUpsert Leave_Balance_Line__c.Fields.Unique_Key__c;
        }

        if (!linesToUpsert.isEmpty()) {
            for (Leave_Balance_Line__c lineRecord : [
                SELECT Id, Unique_Key__c, Leave_Type_Definition__r.Type_Code__c
                FROM Leave_Balance_Line__c
                WHERE Unique_Key__c IN :new Map<String, Leave_Balance_Line__c>(linesToUpsert).keySet()
            ]) {
                String typeCode = lineRecord.Leave_Type_Definition__r.Type_Code__c;
                Decimal grantedQuantity = quotaByTypeCode.containsKey(typeCode)
                    ? quotaByTypeCode.get(typeCode)
                    : 0;
                transactionsToInsert.add(buildTransaction(
                    lineRecord.Id,
                    null,
                    'Grant',
                    grantedQuantity,
                    Date.newInstance(yearValue, 1, 1),
                    'INIT-GRANT-' + lineRecord.Unique_Key__c,
                    'Initial yearly entitlement',
                    1
                ));
            }
            if (!transactionsToInsert.isEmpty()) {
                upsert transactionsToInsert Leave_Balance_Transaction__c.Fields.Idempotency_Key__c;
            }
        }

        syncLegacyBalanceHeads(touchedBalanceIds);
    }

    private static RequestContext loadRequestContext(Id leaveRequestId) {
        RequestContext context = new RequestContext();
        context.requestRecord = [
            SELECT Id, Employee__c, Leave_Type_Definition__c, Leave_Type_Code__c,
                   Start_Date__c, End_Date__c, Status__c, Balance_Deducted__c
            FROM Leave_Request__c
            WHERE Id = :leaveRequestId
        ];
        context.segments = [
            SELECT Id, Balance_Year__c, Days__c, Segment_Start_Date__c, Segment_Status__c, Unique_Key__c
            FROM Leave_Request_Segment__c
            WHERE Leave_Request__c = :leaveRequestId
            ORDER BY Segment_Start_Date__c
        ];
        if (context.segments.isEmpty()
            && context.requestRecord.Start_Date__c != null
            && context.requestRecord.End_Date__c != null) {
            LeaveRequestSegmentService.syncSegments(new List<Leave_Request__c>{ context.requestRecord });
            context.segments = [
                SELECT Id, Balance_Year__c, Days__c, Segment_Start_Date__c, Segment_Status__c, Unique_Key__c
                FROM Leave_Request_Segment__c
                WHERE Leave_Request__c = :leaveRequestId
                ORDER BY Segment_Start_Date__c
            ];
        }
        context.policy = resolvePolicy(
            context.requestRecord.Leave_Type_Definition__c,
            context.requestRecord.Leave_Type_Code__c
        );
        context.lineByYear = ensureLinesForYears(
            context.requestRecord.Employee__c,
            collectBalanceYears(context.segments),
            context.policy,
            false
        );
        return context;
    }

    private static Map<Integer, Leave_Balance_Line__c> ensureLinesForYears(
        Id employeeId,
        Set<Integer> yearValues,
        LeaveTypePolicyService.LeaveTypePolicy policy,
        Boolean autoCreateHeads
    ) {
        Map<Integer, Leave_Balance_Line__c> lineByYear = new Map<Integer, Leave_Balance_Line__c>();
        if (employeeId == null || yearValues.isEmpty() || policy == null) {
            return lineByYear;
        }

        Map<Integer, Leave_Balance__c> balanceByYear = ensureBalanceHeads(employeeId, yearValues, autoCreateHeads);
        Set<String> lineKeys = new Set<String>();
        for (Integer yearValue : yearValues) {
            lineKeys.add(buildLineKey(employeeId, yearValue, policy.typeCode));
        }

        Map<String, Leave_Balance_Line__c> existingByKey = new Map<String, Leave_Balance_Line__c>();
        for (Leave_Balance_Line__c lineRecord : [
            SELECT Id, Leave_Balance__c, Leave_Balance__r.Year__c, Leave_Balance__r.Balance_Year__c,
                   Leave_Type_Definition__c, Opening_Balance__c, Granted__c, Granted_By_Policy__c,
                   Carried_Forward__c, Reserved__c, Used__c, Adjusted__c, Expired__c, Available__c, Unique_Key__c
            FROM Leave_Balance_Line__c
            WHERE Unique_Key__c IN :lineKeys
        ]) {
            existingByKey.put(lineRecord.Unique_Key__c, lineRecord);
        }

        List<Leave_Balance_Line__c> linesToUpsert = new List<Leave_Balance_Line__c>();
        for (Integer yearValue : yearValues) {
            String lineKey = buildLineKey(employeeId, yearValue, policy.typeCode);
            Leave_Balance_Line__c lineRecord = existingByKey.get(lineKey);
            if (lineRecord == null) {
                Leave_Balance__c headRecord = balanceByYear.get(yearValue);
                if (headRecord == null) {
                    continue;
                }
                lineRecord = buildLineFromLegacyHead(headRecord, policy, yearValue);
                linesToUpsert.add(lineRecord);
            }
        }

        if (!linesToUpsert.isEmpty()) {
            upsert linesToUpsert Leave_Balance_Line__c.Fields.Unique_Key__c;
        }

        for (Leave_Balance_Line__c lineRecord : [
            SELECT Id, Leave_Balance__c, Leave_Balance__r.Year__c, Leave_Balance__r.Balance_Year__c,
                   Leave_Type_Definition__c, Opening_Balance__c, Granted__c, Granted_By_Policy__c,
                   Carried_Forward__c, Reserved__c, Used__c, Adjusted__c, Expired__c, Available__c, Unique_Key__c
            FROM Leave_Balance_Line__c
            WHERE Unique_Key__c IN :lineKeys
        ]) {
            Integer yearValue = resolveBalanceYear(
                lineRecord.Leave_Balance__r.Balance_Year__c,
                lineRecord.Leave_Balance__r.Year__c
            );
            lineByYear.put(yearValue, lineRecord);
        }
        return lineByYear;
    }

    private static Map<Integer, Leave_Balance__c> ensureBalanceHeads(
        Id employeeId,
        Set<Integer> yearValues,
        Boolean autoCreateHeads
    ) {
        Map<Integer, Leave_Balance__c> balanceByYear = new Map<Integer, Leave_Balance__c>();
        Set<String> balanceKeys = new Set<String>();
        for (Integer yearValue : yearValues) {
            balanceKeys.add(buildBalanceKey(employeeId, yearValue));
        }

        for (Leave_Balance__c balanceRecord : [
            SELECT Id, User__c, Year__c, Balance_Year__c, Unique_Key__c, Status__c,
                   Annual_Leave__c, Sick_Leave__c, Personal_Leave__c, Carryover_Annual_Leave__c
            FROM Leave_Balance__c
            WHERE Unique_Key__c IN :balanceKeys
        ]) {
            balanceByYear.put(resolveBalanceYear(balanceRecord.Balance_Year__c, balanceRecord.Year__c), balanceRecord);
        }

        if (autoCreateHeads == true) {
            List<Leave_Balance__c> balancesToUpsert = new List<Leave_Balance__c>();
            for (Integer yearValue : yearValues) {
                if (balanceByYear.containsKey(yearValue)) {
                    continue;
                }
                Leave_Balance__c newBalance = new Leave_Balance__c(
                    User__c = employeeId,
                    Year__c = yearValue,
                    Balance_Year__c = yearValue,
                    Status__c = 'Open',
                    Unique_Key__c = buildBalanceKey(employeeId, yearValue),
                    Annual_Leave__c = 0,
                    Sick_Leave__c = 0,
                    Personal_Leave__c = 0,
                    Carryover_Annual_Leave__c = 0
                );
                balancesToUpsert.add(newBalance);
            }

            if (!balancesToUpsert.isEmpty()) {
                upsert balancesToUpsert Leave_Balance__c.Fields.Unique_Key__c;
                for (Leave_Balance__c balanceRecord : balancesToUpsert) {
                    balanceByYear.put(yearValueFromBalance(balanceRecord), balanceRecord);
                }
            }
        }

        for (Leave_Balance__c balanceRecord : [
            SELECT Id, User__c, Year__c, Balance_Year__c, Unique_Key__c, Status__c,
                   Annual_Leave__c, Sick_Leave__c, Personal_Leave__c, Carryover_Annual_Leave__c
            FROM Leave_Balance__c
            WHERE Unique_Key__c IN :balanceKeys
        ]) {
            balanceByYear.put(resolveBalanceYear(balanceRecord.Balance_Year__c, balanceRecord.Year__c), balanceRecord);
        }
        return balanceByYear;
    }

    private static Leave_Balance_Line__c buildLineFromLegacyHead(
        Leave_Balance__c headRecord,
        LeaveTypePolicyService.LeaveTypePolicy policy,
        Integer yearValue
    ) {
        Decimal grantedByPolicy = 0;
        Decimal carriedForward = 0;
        if (policy.typeCode == 'ANNUAL') {
            grantedByPolicy = safeDecimal(headRecord.Annual_Leave__c);
            carriedForward = safeDecimal(headRecord.Carryover_Annual_Leave__c);
        } else if (policy.typeCode == 'SICK') {
            grantedByPolicy = safeDecimal(headRecord.Sick_Leave__c);
        } else if (policy.typeCode == 'PERSONAL') {
            grantedByPolicy = safeDecimal(headRecord.Personal_Leave__c);
        }

        return new Leave_Balance_Line__c(
            Leave_Balance__c = headRecord.Id,
            Leave_Type_Definition__c = policy.definitionId,
            Opening_Balance__c = 0,
            Granted__c = 0,
            Granted_By_Policy__c = grantedByPolicy,
            Carried_Forward__c = carriedForward,
            Reserved__c = 0,
            Used__c = 0,
            Adjusted__c = 0,
            Expired__c = 0,
            Unique_Key__c = buildLineKey(headRecord.User__c, yearValue, policy.typeCode)
        );
    }

    private static List<BalanceSummary> buildSummaries(List<Leave_Balance__c> balances) {
        List<BalanceSummary> summaries = new List<BalanceSummary>();
        if (balances.isEmpty()) {
            return summaries;
        }

        Set<Id> balanceIds = new Set<Id>();
        for (Leave_Balance__c balanceRecord : balances) {
            balanceIds.add(balanceRecord.Id);
        }

        Map<Id, List<Leave_Balance_Line__c>> linesByBalanceId = new Map<Id, List<Leave_Balance_Line__c>>();
        for (Leave_Balance_Line__c lineRecord : [
            SELECT Id, Leave_Balance__c, Available__c, Carried_Forward__c, Reserved__c, Used__c, Expired__c,
                   Leave_Balance__r.Year__c, Leave_Balance__r.Balance_Year__c,
                   Leave_Type_Definition__r.Type_Code__c
            FROM Leave_Balance_Line__c
            WHERE Leave_Balance__c IN :balanceIds
        ]) {
            if (!linesByBalanceId.containsKey(lineRecord.Leave_Balance__c)) {
                linesByBalanceId.put(lineRecord.Leave_Balance__c, new List<Leave_Balance_Line__c>());
            }
            linesByBalanceId.get(lineRecord.Leave_Balance__c).add(lineRecord);
        }

        LeaveTypePolicyService.LeaveTypePolicy annualPolicy =
            LeaveTypePolicyService.getPolicyByTypeCode('ANNUAL');

        for (Leave_Balance__c balanceRecord : balances) {
            BalanceSummary summary = new BalanceSummary();
            summary.name = balanceRecord.Name;
            summary.balanceId = balanceRecord.Id;
            summary.userId = balanceRecord.User__c;
            summary.userName = balanceRecord.User__r == null ? null : balanceRecord.User__r.Name;
            summary.yearValue = balanceRecord.Year__c;
            summary.annualTotalAvailable = 0;
            summary.carryoverAnnualLeave = 0;
            summary.sickLeave = 0;
            summary.personalLeave = 0;

            List<Leave_Balance_Line__c> balanceLines = linesByBalanceId.containsKey(balanceRecord.Id)
                ? linesByBalanceId.get(balanceRecord.Id)
                : new List<Leave_Balance_Line__c>();
            for (Leave_Balance_Line__c lineRecord : balanceLines) {
                String typeCode = lineRecord.Leave_Type_Definition__r == null
                    ? null
                    : lineRecord.Leave_Type_Definition__r.Type_Code__c;
                if (typeCode == 'ANNUAL') {
                    Decimal carryoverAvailable = resolveCarryoverAvailable(
                        lineRecord,
                        annualPolicy,
                        System.today()
                    );
                    summary.carryoverAnnualLeave = carryoverAvailable;
                    summary.annualTotalAvailable = safeDecimal(lineRecord.Available__c);
                    summary.carryoverExpiryDate = resolveCarryoverExpiryDate(
                        annualPolicy,
                        resolveBalanceYear(balanceRecord.Balance_Year__c, balanceRecord.Year__c)
                    );
                } else if (typeCode == 'SICK') {
                    summary.sickLeave = safeDecimal(lineRecord.Available__c);
                } else if (typeCode == 'PERSONAL') {
                    summary.personalLeave = safeDecimal(lineRecord.Available__c);
                }
            }
            summaries.add(summary);
        }
        return summaries;
    }

    private static Map<Id, Leave_Balance_Line__c> queryAnnualLinesByBalanceIds(
        Set<Id> balanceIds,
        LeaveTypePolicyService.LeaveTypePolicy policy
    ) {
        Map<Id, Leave_Balance_Line__c> lineByBalanceId = new Map<Id, Leave_Balance_Line__c>();
        if (balanceIds.isEmpty() || policy == null || policy.definitionId == null) {
            return lineByBalanceId;
        }
        for (Leave_Balance_Line__c lineRecord : [
            SELECT Id, Leave_Balance__c, Leave_Balance__r.Year__c, Leave_Balance__r.Balance_Year__c,
                   Available__c, Carried_Forward__c, Expired__c, Reserved__c, Used__c, Granted__c,
                   Granted_By_Policy__c, Opening_Balance__c, Adjusted__c
            FROM Leave_Balance_Line__c
            WHERE Leave_Balance__c IN :balanceIds
            AND Leave_Type_Definition__c = :policy.definitionId
        ]) {
            lineByBalanceId.put(lineRecord.Leave_Balance__c, lineRecord);
        }
        return lineByBalanceId;
    }

    private static void persistLedgerChanges(
        List<Leave_Balance_Line__c> linesToUpdate,
        List<Leave_Request_Segment__c> segmentsToUpdate,
        List<Leave_Balance_Transaction__c> transactionsToInsert,
        Set<Id> touchedBalanceIds
    ) {
        if (linesToUpdate != null && !linesToUpdate.isEmpty()) {
            update linesToUpdate;
        }
        if (segmentsToUpdate != null && !segmentsToUpdate.isEmpty()) {
            update segmentsToUpdate;
        }
        if (transactionsToInsert != null && !transactionsToInsert.isEmpty()) {
            upsert transactionsToInsert Leave_Balance_Transaction__c.Fields.Idempotency_Key__c;
        }
        syncLegacyBalanceHeads(touchedBalanceIds);
    }

    private static Leave_Balance_Transaction__c buildTransaction(
        Id lineId,
        Id requestId,
        String transactionType,
        Decimal quantity,
        Date businessDate,
        String idempotencyKey,
        String comments,
        Decimal policyVersion
    ) {
        return new Leave_Balance_Transaction__c(
            Leave_Balance_Line__c = lineId,
            Leave_Request__c = requestId,
            Transaction_Type__c = transactionType,
            Quantity__c = quantity,
            Business_Date__c = businessDate,
            Idempotency_Key__c = idempotencyKey,
            Comments__c = comments,
            Policy_Version__c = policyVersion
        );
    }

    private static LeaveTypePolicyService.LeaveTypePolicy resolvePolicy(Id definitionId, String leaveTypeCode) {
        LeaveTypePolicyService.LeaveTypePolicy policy = definitionId == null
            ? null
            : LeaveTypePolicyService.getPolicyByDefinitionId(definitionId);
        if (policy == null) {
            policy = LeaveTypePolicyService.getPolicyByTypeCode(leaveTypeCode);
        }
        if (policy == null || String.isBlank(policy.typeCode)) {
            throw new IllegalArgumentException('Leave type policy is not configured.');
        }
        if (policy.definitionId == null) {
            throw new IllegalArgumentException(
                'Leave type ' + policy.typeCode + ' is not yet supported by the current balance ledger.'
            );
        }
        return policy;
    }

    private static Set<Integer> collectBalanceYears(List<LeaveRequestSegmentService.SegmentDetail> segments) {
        Set<Integer> yearValues = new Set<Integer>();
        for (LeaveRequestSegmentService.SegmentDetail segment : segments) {
            yearValues.add(segment.balanceYear);
        }
        return yearValues;
    }

    private static Set<Integer> collectBalanceYears(List<Leave_Request_Segment__c> segments) {
        Set<Integer> yearValues = new Set<Integer>();
        for (Leave_Request_Segment__c segment : segments) {
            yearValues.add(Integer.valueOf(String.valueOf(segment.Balance_Year__c)));
        }
        return yearValues;
    }

    private static Decimal calculateEffectiveAvailable(
        Leave_Balance_Line__c lineRecord,
        LeaveTypePolicyService.LeaveTypePolicy policy,
        Date businessDate
    ) {
        Decimal available = safeDecimal(lineRecord.Available__c);
        Decimal carryoverAvailable = resolveCarryoverAvailable(lineRecord, policy, businessDate);
        Decimal storedCarryover = safeDecimal(lineRecord.Carried_Forward__c);
        if (storedCarryover > carryoverAvailable) {
            available -= (storedCarryover - carryoverAvailable);
        }
        return Math.max(available, 0);
    }

    private static Decimal resolveCarryoverAvailable(
        Leave_Balance_Line__c lineRecord,
        LeaveTypePolicyService.LeaveTypePolicy policy,
        Date businessDate
    ) {
        if (policy == null || policy.allowCarryover != true) {
            return 0;
        }
        Decimal carryoverAmount = Math.max(
            safeDecimal(lineRecord.Carried_Forward__c)
                - safeDecimal(lineRecord.Reserved__c)
                - safeDecimal(lineRecord.Used__c)
                - safeDecimal(lineRecord.Expired__c),
            0
        );
        if (carryoverAmount <= 0) {
            return 0;
        }

        Integer yearValue = resolveBalanceYear(
            lineRecord.Leave_Balance__r == null ? null : lineRecord.Leave_Balance__r.Balance_Year__c,
            lineRecord.Leave_Balance__r == null ? null : lineRecord.Leave_Balance__r.Year__c
        );
        Date expiryDate = resolveCarryoverExpiryDate(policy, yearValue);
        if (expiryDate != null && (businessDate == null ? System.today() : businessDate) > expiryDate) {
            return 0;
        }
        return Math.min(carryoverAmount, safeDecimal(lineRecord.Available__c));
    }

    private static Date resolveCarryoverExpiryDate(
        LeaveTypePolicyService.LeaveTypePolicy policy,
        Integer yearValue
    ) {
        if (policy == null || policy.allowCarryover != true || yearValue == null) {
            return null;
        }
        if (policy.carryoverExpireMonth == null || policy.carryoverExpireDay == null) {
            return null;
        }
        return buildExpiryDate(yearValue, policy.carryoverExpireMonth, policy.carryoverExpireDay);
    }

    private static String buildMissingBalanceMessage(Integer balanceYear) {
        return 'No leave balance found. Please contact HR to set up leave balance for year ' +
            String.valueOf(balanceYear) + '.';
    }

    private static Map<Integer, Decimal> summarizeExistingActiveUsage(
        Id employeeId,
        String leaveTypeCode,
        Id excludeRequestId
    ) {
        Map<Integer, Decimal> daysByYear = new Map<Integer, Decimal>();
        if (employeeId == null || String.isBlank(leaveTypeCode)) {
            return daysByYear;
        }

        for (Leave_Request__c existingRequest : [
            SELECT Start_Date__c, End_Date__c
            FROM Leave_Request__c
            WHERE Employee__c = :employeeId
            AND Leave_Type_Code__c = :leaveTypeCode
            AND Id != :excludeRequestId
            AND Status__c IN ('Submitted', 'Pending_Manager_Approval', 'Pending_HR_Approval', 'Approved')
        ]) {
            Map<Integer, Decimal> existingDaysByYear =
                LeaveRequestSegmentService.summarizeDaysByYear(
                    existingRequest.Start_Date__c,
                    existingRequest.End_Date__c
                );
            for (Integer yearValue : existingDaysByYear.keySet()) {
                Decimal accumulated = daysByYear.containsKey(yearValue)
                    ? daysByYear.get(yearValue)
                    : 0;
                daysByYear.put(yearValue, accumulated + existingDaysByYear.get(yearValue));
            }
        }
        return daysByYear;
    }

    private static String buildBalanceKey(Id userId, Integer yearValue) {
        return String.valueOf(userId) + '-' + String.valueOf(yearValue);
    }

    private static String buildLineKey(Id userId, Integer yearValue, String typeCode) {
        return String.valueOf(userId) + '-' + String.valueOf(yearValue) + '-' + String.valueOf(typeCode);
    }

    private static String buildIdempotencyKey(String prefix, Id requestId, String segmentKey) {
        return prefix + '-' + String.valueOf(requestId) + '-' + segmentKey;
    }

    private static Integer resolveBalanceYear(Decimal balanceYearValue, Decimal legacyYearValue) {
        if (balanceYearValue != null) {
            return Integer.valueOf(String.valueOf(balanceYearValue));
        }
        if (legacyYearValue != null) {
            return Integer.valueOf(String.valueOf(legacyYearValue));
        }
        return System.today().year();
    }

    private static Integer yearValueFromBalance(Leave_Balance__c balanceRecord) {
        return resolveBalanceYear(balanceRecord.Balance_Year__c, balanceRecord.Year__c);
    }

    private static Decimal safeDecimal(Decimal value) {
        return value == null ? 0 : value;
    }

    private static Date buildExpiryDate(Integer yearValue, Integer expiryMonth, Integer expiryDay) {
        Date firstDayOfMonth = Date.newInstance(yearValue, expiryMonth, 1);
        Integer lastDayOfMonth = firstDayOfMonth.addMonths(1).addDays(-1).day();
        Integer safeDay = Math.min(expiryDay, lastDayOfMonth);
        return Date.newInstance(yearValue, expiryMonth, safeDay);
    }

    private static Set<String> queryExistingTransactionKeys(Set<String> exactKeys, String keyPrefix) {
        Set<String> existingKeys = new Set<String>();
        if ((exactKeys == null || exactKeys.isEmpty()) && String.isBlank(keyPrefix)) {
            return existingKeys;
        }

        String prefixValue = String.isBlank(keyPrefix) ? null : keyPrefix + '%';
        for (Leave_Balance_Transaction__c transactionRecord : [
            SELECT Idempotency_Key__c
            FROM Leave_Balance_Transaction__c
            WHERE Idempotency_Key__c IN :exactKeys
            OR Idempotency_Key__c LIKE :prefixValue
        ]) {
            existingKeys.add(transactionRecord.Idempotency_Key__c);
        }
        return existingKeys;
    }

    private static void carryForwardLegacyAnnualLeave(
        List<Leave_Balance__c> sourceBalances,
        Integer sourceYear,
        Integer targetYear,
        Decimal carryoverLimit,
        Integer expiryMonth,
        Integer expiryDay
    ) {
        Set<Id> userIds = new Set<Id>();
        for (Leave_Balance__c sourceBalance : sourceBalances) {
            if (sourceBalance.User__c != null) {
                userIds.add(sourceBalance.User__c);
            }
        }
        List<Leave_Balance__c> targetBalances = [
            SELECT Id, User__c, Year__c, Balance_Year__c, Unique_Key__c, Status__c,
                   Annual_Leave__c, Sick_Leave__c, Personal_Leave__c, Carryover_Annual_Leave__c
            FROM Leave_Balance__c
            WHERE Year__c = :targetYear
            AND User__c IN :userIds
        ];
        Map<Id, Leave_Balance__c> targetByUserId = new Map<Id, Leave_Balance__c>();
        for (Leave_Balance__c targetBalance : targetBalances) {
            targetByUserId.put(targetBalance.User__c, targetBalance);
        }

        String carryoverRunKey = 'ANNUAL-' + sourceYear + '-' + targetYear;
        Date expiryDate = buildExpiryDate(targetYear, expiryMonth, expiryDay);
        List<Leave_Balance__c> balancesToUpsert = new List<Leave_Balance__c>();
        for (Leave_Balance__c sourceBalance : sourceBalances) {
            Decimal available = safeDecimal(sourceBalance.Annual_Leave__c)
                + safeDecimal(sourceBalance.Carryover_Annual_Leave__c);
            Decimal carryoverAmount = Math.min(Math.max(available, 0), carryoverLimit);
            if (carryoverAmount <= 0) {
                continue;
            }

            Leave_Balance__c targetBalance = targetByUserId.get(sourceBalance.User__c);
            if (targetBalance == null) {
                targetBalance = new Leave_Balance__c(
                    User__c = sourceBalance.User__c,
                    Year__c = targetYear,
                    Balance_Year__c = targetYear,
                    Status__c = 'Open',
                    Unique_Key__c = buildBalanceKey(sourceBalance.User__c, targetYear),
                    Annual_Leave__c = 0,
                    Sick_Leave__c = 0,
                    Personal_Leave__c = 0
                );
            }

            targetBalance.Carryover_Annual_Leave__c = carryoverAmount;
            targetBalance.Carryover_Expiry_Date__c = expiryDate;
            targetBalance.Carryover_Source_Year__c = sourceYear;
            targetBalance.Carryover_Run_Key__c = carryoverRunKey;
            balancesToUpsert.add(targetBalance);
        }

        if (!balancesToUpsert.isEmpty()) {
            upsert balancesToUpsert Leave_Balance__c.Fields.Unique_Key__c;
        }
    }

    private static Integer expireLegacyCarryover(Date effectiveDate) {
        List<Leave_Balance__c> balancesToUpdate = new List<Leave_Balance__c>();
        for (Leave_Balance__c balanceRecord : [
            SELECT Id, Carryover_Annual_Leave__c, Carryover_Expiry_Date__c
            FROM Leave_Balance__c
            WHERE Carryover_Annual_Leave__c > 0
            AND Carryover_Expiry_Date__c != null
            AND Carryover_Expiry_Date__c < :effectiveDate
        ]) {
            balanceRecord.Carryover_Annual_Leave__c = 0;
            balancesToUpdate.add(balanceRecord);
        }
        if (!balancesToUpdate.isEmpty()) {
            update balancesToUpdate;
        }
        return balancesToUpdate.size();
    }

    private static void applyCarryoverHeadMetadata(
        Set<Id> balanceIds,
        Integer sourceYear,
        Integer targetYear,
        Integer expiryMonth,
        Integer expiryDay
    ) {
        List<Leave_Balance__c> balancesToUpdate = new List<Leave_Balance__c>();
        String carryoverRunKey = 'ANNUAL-' + sourceYear + '-' + targetYear;
        Date expiryDate = buildExpiryDate(targetYear, expiryMonth, expiryDay);
        for (Leave_Balance__c balanceRecord : [
            SELECT Id, Carryover_Annual_Leave__c
            FROM Leave_Balance__c
            WHERE Id IN :balanceIds
        ]) {
            if (safeDecimal(balanceRecord.Carryover_Annual_Leave__c) <= 0) {
                continue;
            }
            balanceRecord.Carryover_Source_Year__c = sourceYear;
            balanceRecord.Carryover_Run_Key__c = carryoverRunKey;
            balanceRecord.Carryover_Expiry_Date__c = expiryDate;
            balancesToUpdate.add(balanceRecord);
        }
        if (!balancesToUpdate.isEmpty()) {
            update balancesToUpdate;
        }
    }
}
