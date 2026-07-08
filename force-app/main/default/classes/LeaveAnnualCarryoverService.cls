public without sharing class LeaveAnnualCarryoverService {

    public static final Decimal DEFAULT_CARRYOVER_LIMIT = 5;
    public static final Integer DEFAULT_EXPIRY_MONTH = 3;
    public static final Integer DEFAULT_EXPIRY_DAY = 31;

    public static void carryForwardAnnualLeave(Integer sourceYear, Integer targetYear) {
        carryForwardAnnualLeave(
            sourceYear,
            targetYear,
            DEFAULT_CARRYOVER_LIMIT,
            DEFAULT_EXPIRY_MONTH,
            DEFAULT_EXPIRY_DAY
        );
    }

    public static void carryForwardAnnualLeave(
        Integer sourceYear,
        Integer targetYear,
        Decimal carryoverLimit,
        Integer expiryMonth,
        Integer expiryDay
    ) {
        validateCarryoverArguments(sourceYear, targetYear, carryoverLimit, expiryMonth, expiryDay);
        LeaveTypePolicyService.LeaveTypePolicy policy = LeaveTypePolicyService.getPolicyByTypeCode('ANNUAL');
        if (policy.isDefined && !policy.isActive) {
            return;
        }
        if (policy.allowCarryover == false) {
            return;
        }

        Decimal effectiveCarryoverLimit = policy.carryoverLimit == null ? carryoverLimit : policy.carryoverLimit;
        Integer effectiveExpiryMonth = policy.carryoverExpireMonth == null ? expiryMonth : policy.carryoverExpireMonth;
        Integer effectiveExpiryDay = policy.carryoverExpireDay == null ? expiryDay : policy.carryoverExpireDay;

        validateCarryoverArguments(
            sourceYear,
            targetYear,
            effectiveCarryoverLimit,
            effectiveExpiryMonth,
            effectiveExpiryDay
        );

        List<Leave_Balance__c> sourceBalances = [
            SELECT Id, User__c, Annual_Leave__c
            FROM Leave_Balance__c
            WHERE Year__c = :sourceYear
            AND User__c != null
        ];

        if (sourceBalances.isEmpty()) {
            return;
        }

        Set<String> targetKeys = new Set<String>();
        for (Leave_Balance__c sourceBalance : sourceBalances) {
            targetKeys.add(buildBalanceKey(sourceBalance.User__c, targetYear));
        }

        Map<String, Leave_Balance__c> targetBalanceByKey = new Map<String, Leave_Balance__c>();
        for (Leave_Balance__c targetBalance : [
            SELECT Id, Unique_Key__c, User__c, Year__c, Annual_Leave__c, Sick_Leave__c, Personal_Leave__c,
                   Carryover_Annual_Leave__c, Carryover_Expiry_Date__c, Carryover_Source_Year__c, Carryover_Run_Key__c
            FROM Leave_Balance__c
            WHERE Unique_Key__c IN :targetKeys
        ]) {
            targetBalanceByKey.put(targetBalance.Unique_Key__c, targetBalance);
        }

        List<Leave_Balance__c> balancesToUpsert = new List<Leave_Balance__c>();
        String runKey = 'ANNUAL-' + sourceYear + '-' + targetYear;

        for (Leave_Balance__c sourceBalance : sourceBalances) {
            String targetKey = buildBalanceKey(sourceBalance.User__c, targetYear);
            Leave_Balance__c targetBalance = targetBalanceByKey.get(targetKey);
            if (targetBalance == null) {
                targetBalance = new Leave_Balance__c(
                    User__c = sourceBalance.User__c,
                    Year__c = targetYear,
                    Unique_Key__c = targetKey,
                    Annual_Leave__c = 0,
                    Sick_Leave__c = 0,
                    Personal_Leave__c = 0
                );
            }

            if (targetBalance.Carryover_Source_Year__c == sourceYear &&
                targetBalance.Carryover_Run_Key__c == runKey) {
                continue;
            }

            Decimal carryoverAmount = Math.max(
                sourceBalance.Annual_Leave__c == null ? 0 : sourceBalance.Annual_Leave__c,
                0
            );
            carryoverAmount = Math.min(carryoverAmount, effectiveCarryoverLimit);

            targetBalance.Carryover_Annual_Leave__c = carryoverAmount;
            targetBalance.Carryover_Expiry_Date__c = buildExpiryDate(targetYear, effectiveExpiryMonth, effectiveExpiryDay);
            targetBalance.Carryover_Source_Year__c = sourceYear;
            targetBalance.Carryover_Run_Key__c = runKey;

            balancesToUpsert.add(targetBalance);
        }

        if (!balancesToUpsert.isEmpty()) {
            upsert balancesToUpsert Leave_Balance__c.Fields.Unique_Key__c;
        }
    }

    public static Integer expireCarryover(Date asOfDate) {
        Date effectiveDate = asOfDate == null ? System.today() : asOfDate;
        List<Leave_Balance__c> balancesToUpdate = [
            SELECT Id, Carryover_Annual_Leave__c
            FROM Leave_Balance__c
            WHERE Carryover_Annual_Leave__c > 0
            AND Carryover_Expiry_Date__c < :effectiveDate
        ];

        for (Leave_Balance__c balance : balancesToUpdate) {
            balance.Carryover_Annual_Leave__c = 0;
        }

        if (!balancesToUpdate.isEmpty()) {
            update balancesToUpdate;
        }

        return balancesToUpdate.size();
    }

    private static void validateCarryoverArguments(
        Integer sourceYear,
        Integer targetYear,
        Decimal carryoverLimit,
        Integer expiryMonth,
        Integer expiryDay
    ) {
        if (sourceYear == null || targetYear == null) {
            throw new IllegalArgumentException('Source year and target year are required.');
        }
        if (targetYear != sourceYear + 1) {
            throw new IllegalArgumentException('Target year must be the next calendar year.');
        }
        if (carryoverLimit == null || carryoverLimit < 0) {
            throw new IllegalArgumentException('Carryover limit must be zero or greater.');
        }
        if (expiryMonth == null || expiryMonth < 1 || expiryMonth > 12) {
            throw new IllegalArgumentException('Expiry month must be between 1 and 12.');
        }
        if (expiryDay == null || expiryDay < 1 || expiryDay > 31) {
            throw new IllegalArgumentException('Expiry day must be between 1 and 31.');
        }
    }

    private static String buildBalanceKey(Id userId, Integer yearValue) {
        return String.valueOf(userId) + '-' + String.valueOf(yearValue);
    }

    private static Date buildExpiryDate(Integer targetYear, Integer expiryMonth, Integer expiryDay) {
        Date firstDayOfMonth = Date.newInstance(targetYear, expiryMonth, 1);
        Integer lastDayOfMonth = firstDayOfMonth.addMonths(1).addDays(-1).day();
        Integer safeDay = Math.min(expiryDay, lastDayOfMonth);
        return Date.newInstance(targetYear, expiryMonth, safeDay);
    }
}
