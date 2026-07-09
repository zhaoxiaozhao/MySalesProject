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
        LeaveBalanceLedgerService.carryForwardAnnualLeave(
            sourceYear,
            targetYear,
            effectiveCarryoverLimit,
            effectiveExpiryMonth,
            effectiveExpiryDay
        );
    }

    public static Integer expireCarryover(Date asOfDate) {
        return LeaveBalanceLedgerService.expireCarryover(asOfDate);
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

    private static Date buildExpiryDate(Integer targetYear, Integer expiryMonth, Integer expiryDay) {
        Date firstDayOfMonth = Date.newInstance(targetYear, expiryMonth, 1);
        Integer lastDayOfMonth = firstDayOfMonth.addMonths(1).addDays(-1).day();
        Integer safeDay = Math.min(expiryDay, lastDayOfMonth);
        return Date.newInstance(targetYear, expiryMonth, safeDay);
    }
}
