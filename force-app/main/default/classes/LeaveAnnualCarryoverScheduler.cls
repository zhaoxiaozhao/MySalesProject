global class LeaveAnnualCarryoverScheduler implements Schedulable {

    global void execute(SchedulableContext sc) {
        Integer targetYear = System.today().year();
        Integer sourceYear = targetYear - 1;

        LeaveAnnualCarryoverService.carryForwardAnnualLeave(sourceYear, targetYear);
        LeaveAnnualCarryoverService.expireCarryover(System.today());
    }
}
