public without sharing class LeaveSetupInitializationJob implements Queueable {

    private final Integer yearValue;
    private final Decimal annualDays;
    private final Decimal sickDays;
    private final Decimal personalDays;
    private final Boolean overwriteExistingBalances;

    public LeaveSetupInitializationJob(Integer yearValue) {
        this(
            yearValue,
            LeaveSetupInitializationService.DEFAULT_ANNUAL_DAYS,
            LeaveSetupInitializationService.DEFAULT_SICK_DAYS,
            LeaveSetupInitializationService.DEFAULT_PERSONAL_DAYS,
            false
        );
    }

    public LeaveSetupInitializationJob(
        Integer yearValue,
        Decimal annualDays,
        Decimal sickDays,
        Decimal personalDays,
        Boolean overwriteExistingBalances
    ) {
        this.yearValue = yearValue;
        this.annualDays = annualDays;
        this.sickDays = sickDays;
        this.personalDays = personalDays;
        this.overwriteExistingBalances = overwriteExistingBalances;
    }

    public void execute(QueueableContext context) {
        LeaveSetupInitializationService.initializeDefaultConfiguration(
            yearValue,
            annualDays,
            sickDays,
            personalDays,
            overwriteExistingBalances
        );
    }

    public static Id enqueueDefaultSetup(Integer yearValue) {
        return System.enqueueJob(new LeaveSetupInitializationJob(yearValue));
    }
}
