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

    @IsTest
    static void testHrApprovalResolvesQueueMemberApprover() {
        User approver = createUser('hrqueue');
        Group queueGroup = new Group(
            Name = 'HR Queue Routing',
            DeveloperName = 'HR_QUEUE_ROUTING',
            Type = 'Queue'
        );
        insert queueGroup;
        insert new GroupMember(
            GroupId = queueGroup.Id,
            UserOrGroupId = approver.Id
        );

        LeaveApprovalRoutingService.clearApproverResolverCache();

        Leave_Request__c requestRecord = new Leave_Request__c(
            Status__c = 'Pending_HR_Approval',
            Approval_Target_Snapshot__c = 'HR_QUEUE_ROUTING'
        );

        Assert.areEqual(
            approver.Id,
            LeaveApprovalRoutingService.resolveApproverId(requestRecord, 'Submit', 'Submitted')
        );
        Assert.areEqual(
            approver.Id,
            LeaveApprovalRoutingService.resolveApproverId(requestRecord, 'HR_Approval', 'Approved')
        );
        Assert.areEqual(
            'HR_QUEUE_ROUTING',
            LeaveApprovalRoutingService.resolveApproverTarget(requestRecord, 'HR_Approval', 'Approved')
        );
    }

    @IsTest
    static void testHrApprovalResolvesNestedGroupMemberAndDirectUserId() {
        User approver = createUser('nestedgrp');
        Group childGroup = new Group(
            Name = 'Child Routing Group',
            DeveloperName = 'CHILD_ROUTING_GROUP',
            Type = 'Regular'
        );
        Group parentGroup = new Group(
            Name = 'Parent Routing Group',
            DeveloperName = 'PARENT_ROUTING_GROUP',
            Type = 'Regular'
        );
        insert new List<Group>{ childGroup, parentGroup };
        insert new List<GroupMember>{
            new GroupMember(
                GroupId = childGroup.Id,
                UserOrGroupId = approver.Id
            ),
            new GroupMember(
                GroupId = parentGroup.Id,
                UserOrGroupId = childGroup.Id
            )
        };

        LeaveApprovalRoutingService.clearApproverResolverCache();

        Leave_Request__c nestedTargetRequest = new Leave_Request__c(
            Status__c = 'Pending_HR_Approval',
            Approval_Target_Snapshot__c = 'PARENT_ROUTING_GROUP'
        );
        Leave_Request__c directUserTargetRequest = new Leave_Request__c(
            Status__c = 'Pending_HR_Approval',
            Approval_Target_Snapshot__c = approver.Id
        );

        Assert.areEqual(
            approver.Id,
            LeaveApprovalRoutingService.resolveApproverId(nestedTargetRequest, 'HR_Approval', 'Approved')
        );
        Assert.areEqual(
            approver.Id,
            LeaveApprovalRoutingService.resolveApproverId(directUserTargetRequest, 'HR_Approval', 'Approved')
        );
    }

    private static User createUser(String key) {
        User currentUser = [
            SELECT ProfileId
            FROM User
            WHERE Id = :UserInfo.getUserId()
        ];
        String uniqueToken = key + String.valueOf(DateTime.now().getTime());
        User userRecord = new User(
            Alias = uniqueToken.substring(0, Math.min(8, uniqueToken.length())),
            Email = uniqueToken + '@example.com',
            EmailEncodingKey = 'UTF-8',
            LastName = 'Routing',
            LanguageLocaleKey = 'en_US',
            LocaleSidKey = 'en_US',
            ProfileId = currentUser.ProfileId,
            TimeZoneSidKey = 'America/Los_Angeles',
            Username = uniqueToken + '@example.com'
        );
        insert userRecord;
        return userRecord;
    }
}
