@IsTest
private class TestVerifyDate {

    @IsTest
    static void testCheckDatesReturnsSecondDateWhenWithinThirtyDays() {
        Date startDate = Date.newInstance(2026, 1, 10);
        Date candidateDate = startDate.addDays(10);

        Date result = VerifyDate.CheckDates(startDate, candidateDate);

        Assert.areEqual(candidateDate, result, '30 天内的日期应直接返回 date2');
    }

    @IsTest
    static void testCheckDatesReturnsEndOfMonthWhenSecondDateIsPast() {
        Date startDate = Date.newInstance(2026, 3, 15);
        Date candidateDate = startDate.addDays(-1);

        Date result = VerifyDate.CheckDates(startDate, candidateDate);

        Assert.areEqual(Date.newInstance(2026, 3, 31), result, '过去日期应回退到当月最后一天');
    }

    @IsTest
    static void testCheckDatesReturnsEndOfMonthWhenSecondDateIsExactlyThirtyDaysLater() {
        Date startDate = Date.newInstance(2026, 2, 10);
        Date candidateDate = startDate.addDays(30);

        Date result = VerifyDate.CheckDates(startDate, candidateDate);

        Assert.areEqual(Date.newInstance(2026, 2, 28), result, '恰好 30 天后不属于 30 天内，应回退到当月最后一天');
    }
}
