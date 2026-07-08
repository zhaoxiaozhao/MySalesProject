global class LeaveExpiryScheduler implements Schedulable {
    global void execute(SchedulableContext sc) {
        LeaveExpiryBatch batch = new LeaveExpiryBatch();
        Database.executeBatch(batch, 200);
    }
}
