@IsTest
private class LeaveApprovalRoutingServiceTest {

    @IsTest
    static void testHrOnlyPolicyRoutesDirectlyToHr() {
        Leave_Request__c requestRecord = new Leave_Request__c(Days__c = 2);
        LeaveTypePolicyService.LeaveTypePolicy policy = new LeaveTypePolicyService.LeaveTypePolicy();
        policy.approvalMode = 'HR Only';

        LeaveApprovalRoutingService.RoutingDecision decision =
            LeaveApprovalRoutingService.resolveSubmissionDecision(requestRecord, policy, null);

        Assert.areEqual('Pending_HR_Approval', decision.nextStatus);
        Assert.areEqual('HR Only', decision.approvalModeSnapshot);
        Assert.areEqual('HR', decision.approvalTargetSnapshot);
    }

    @IsTest
    static void testConfigurablePolicyEscalatesToCustomQueue() {
        Leave_Request__c requestRecord = new Leave_Request__c(Days__c = 5);
        LeaveTypePolicyService.LeaveTypePolicy policy = new LeaveTypePolicyService.LeaveTypePolicy();
        policy.approvalMode = 'Configurable';
        policy.escalateAboveDays = 3;
        policy.escalationTarget = 'Custom Queue';
        policy.approvalGroupKey = 'HR_SPECIAL';

        LeaveApprovalRoutingService.RoutingDecision decision =
            LeaveApprovalRoutingService.resolveSubmissionDecision(requestRecord, policy, null);

        Assert.areEqual('Pending_HR_Approval', decision.nextStatus);
        Assert.areEqual('HR Only', decision.approvalModeSnapshot);
        Assert.areEqual('HR_SPECIAL', decision.approvalTargetSnapshot);
    }

    @IsTest
    static void testManagerOnlyRequiresManager() {
        Leave_Request__c requestRecord = new Leave_Request__c(Days__c = 2);
        LeaveTypePolicyService.LeaveTypePolicy policy = new LeaveTypePolicyService.LeaveTypePolicy();
        policy.approvalMode = 'Manager Only';

        try {
            LeaveApprovalRoutingService.resolveSubmissionDecision(requestRecord, policy, null);
            Assert.fail('Missing manager should raise an exception.');
        } catch (IllegalArgumentException ex) {
            Assert.isTrue(ex.getMessage().contains('manager'));
        }
    }

    @IsTest
    static void testApproverResolutionCoversFallbackBranches() {
        Leave_Request__c requestRecord = new Leave_Request__c(
            Manager__c = UserInfo.getUserId(),
            Status__c = 'Pending_HR_Approval',
            Approval_Target_Snapshot__c = 'HR_ESCALATION'
        );

        Assert.areEqual(
            UserInfo.getUserId(),
            LeaveApprovalRoutingService.resolveApproverId(requestRecord, 'Manager_Approval', 'Approved')
        );
        Assert.areEqual(
            null,
            LeaveApprovalRoutingService.resolveApproverId(requestRecord, 'HR_Approval', 'Approved')
        );
        Assert.areEqual(
            'HR_ESCALATION',
            LeaveApprovalRoutingService.resolveApproverTarget(requestRecord, 'HR_Approval', 'Approved')
        );
        Assert.areEqual(
            'Auto',
            LeaveApprovalRoutingService.resolveApproverTarget(
                new Leave_Request__c(Status__c = 'Approved'),
                'Submit',
                'Approved'
            )
        );
        Assert.areEqual(
            'System',
            LeaveApprovalRoutingService.resolveApproverTarget(
                new Leave_Request__c(),
                'Cancellation',
                'Cancelled'
            )
        );
    }
}
