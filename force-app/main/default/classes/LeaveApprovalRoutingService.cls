public without sharing class LeaveApprovalRoutingService {

    @TestVisible
    private static Map<String, Id> approverIdByTargetCache = new Map<String, Id>();

    public class RoutingDecision {
        public String nextStatus;
        public String approvalModeSnapshot;
        public String approvalTargetSnapshot;
    }

    public static RoutingDecision resolveSubmissionDecision(
        Leave_Request__c requestRecord,
        LeaveTypePolicyService.LeaveTypePolicy policy,
        Id managerId
    ) {
        RoutingDecision decision = new RoutingDecision();
        String approvalMode = normalizeApprovalMode(policy);

        if (policy.autoApproveBelowDays != null &&
            requestRecord.Days__c != null &&
            requestRecord.Days__c <= policy.autoApproveBelowDays) {
            decision.nextStatus = 'Approved';
            decision.approvalModeSnapshot = 'Auto Approve';
            decision.approvalTargetSnapshot = 'Auto';
            return decision;
        }

        if (approvalMode == 'HR Only') {
            decision.nextStatus = 'Pending_HR_Approval';
            decision.approvalModeSnapshot = 'HR Only';
            decision.approvalTargetSnapshot = getHrTarget(policy);
            return decision;
        }

        if (approvalMode == 'Manager Then HR') {
            validateManagerAvailability(managerId);
            decision.nextStatus = 'Submitted';
            decision.approvalModeSnapshot = 'Manager Then HR';
            decision.approvalTargetSnapshot = getHrTarget(policy);
            return decision;
        }

        if (approvalMode == 'Configurable') {
            if (policy.escalateAboveDays != null &&
                requestRecord.Days__c != null &&
                requestRecord.Days__c > policy.escalateAboveDays &&
                getHrEscalationTargets().contains(policy.escalationTarget)) {
                decision.nextStatus = 'Pending_HR_Approval';
                decision.approvalModeSnapshot = 'HR Only';
                decision.approvalTargetSnapshot = getHrTarget(policy);
                return decision;
            }

            if (policy.requiresHrApproval) {
                validateManagerAvailability(managerId);
                decision.nextStatus = 'Submitted';
                decision.approvalModeSnapshot = 'Manager Then HR';
                decision.approvalTargetSnapshot = getHrTarget(policy);
                return decision;
            }
        }

        validateManagerAvailability(managerId);
        decision.nextStatus = 'Submitted';
        decision.approvalModeSnapshot = 'Manager Only';
        decision.approvalTargetSnapshot = 'Manager';
        return decision;
    }

    public static String resolveManagerApprovalStatus(Leave_Request__c requestRecord) {
        return requestRecord.Approval_Mode_Snapshot__c == 'Manager Then HR'
            ? 'Pending_HR_Approval'
            : 'Approved';
    }

    public static Id resolveApproverId(
        Leave_Request__c requestRecord,
        String stage,
        String action
    ) {
        if (stage == 'Manager_Approval') {
            return requestRecord.Manager__c;
        }
        if (stage == 'Submit' && action == 'Submitted' &&
            isManagerPendingStatus(requestRecord.Status__c)) {
            return requestRecord.Manager__c;
        }
        if (stage == 'HR_Approval') {
            return resolveConfiguredApproverId(requestRecord.Approval_Target_Snapshot__c);
        }
        if (stage == 'Submit' && action == 'Submitted' &&
            requestRecord.Status__c == 'Pending_HR_Approval') {
            return resolveConfiguredApproverId(requestRecord.Approval_Target_Snapshot__c);
        }
        return null;
    }

    public static String resolveApproverTarget(
        Leave_Request__c requestRecord,
        String stage,
        String action
    ) {
        if (stage == 'Manager_Approval') {
            return 'Manager';
        }
        if (stage == 'HR_Approval') {
            return String.isBlank(requestRecord.Approval_Target_Snapshot__c)
                ? 'HR'
                : requestRecord.Approval_Target_Snapshot__c;
        }
        if (stage == 'Submit' && action == 'Submitted') {
            if (isManagerPendingStatus(requestRecord.Status__c)) {
                return 'Manager';
            }
            if (requestRecord.Status__c == 'Pending_HR_Approval') {
                return String.isBlank(requestRecord.Approval_Target_Snapshot__c)
                    ? 'HR'
                    : requestRecord.Approval_Target_Snapshot__c;
            }
            if (requestRecord.Status__c == 'Approved') {
                return 'Auto';
            }
        }
        if (stage == 'Submit' && action == 'Approved') {
            return 'Auto';
        }
        return String.isBlank(requestRecord.Approval_Target_Snapshot__c)
            ? 'System'
            : requestRecord.Approval_Target_Snapshot__c;
    }

    private static String normalizeApprovalMode(LeaveTypePolicyService.LeaveTypePolicy policy) {
        if (policy == null || String.isBlank(policy.approvalMode)) {
            return 'Manager Only';
        }
        return policy.approvalMode;
    }

    private static Boolean isManagerPendingStatus(String statusValue) {
        return statusValue == 'Submitted' || statusValue == 'Pending_Manager_Approval';
    }

    private static void validateManagerAvailability(Id managerId) {
        if (managerId == null) {
            throw new IllegalArgumentException('Employee manager is required for the selected approval policy.');
        }
    }

    private static String getHrTarget(LeaveTypePolicyService.LeaveTypePolicy policy) {
        return String.isBlank(policy.approvalGroupKey) ? 'HR' : policy.approvalGroupKey;
    }

    private static Set<String> getHrEscalationTargets() {
        return new Set<String>{ 'HR', 'Custom Queue' };
    }

    @TestVisible
    static void clearApproverResolverCache() {
        approverIdByTargetCache.clear();
    }

    private static Id resolveConfiguredApproverId(String approvalTarget) {
        if (String.isBlank(approvalTarget) || isVirtualApprovalTarget(approvalTarget)) {
            return null;
        }
        if (approverIdByTargetCache.containsKey(approvalTarget)) {
            return approverIdByTargetCache.get(approvalTarget);
        }

        Id resolvedApproverId = tryResolveDirectUserId(approvalTarget);
        if (resolvedApproverId == null) {
            resolvedApproverId = resolveGroupMemberApproverId(approvalTarget);
        }
        approverIdByTargetCache.put(approvalTarget, resolvedApproverId);
        return resolvedApproverId;
    }

    private static Boolean isVirtualApprovalTarget(String approvalTarget) {
        return approvalTarget == 'HR'
            || approvalTarget == 'Manager'
            || approvalTarget == 'Auto'
            || approvalTarget == 'System';
    }

    private static Id tryResolveDirectUserId(String approvalTarget) {
        try {
            Id targetId = (Id) approvalTarget;
            if (targetId.getSObjectType() == User.SObjectType) {
                return targetId;
            }
        } catch (Exception ex) {
            return null;
        }
        return null;
    }

    private static Id resolveGroupMemberApproverId(String approvalTarget) {
        List<Group> groups = [
            SELECT Id
            FROM Group
            WHERE DeveloperName = :approvalTarget OR Name = :approvalTarget
            ORDER BY DeveloperName
            LIMIT 1
        ];
        if (groups.isEmpty()) {
            return null;
        }
        return resolveFirstUserMember(groups[0].Id, new Set<Id>());
    }

    private static Id resolveFirstUserMember(Id groupId, Set<Id> visitedGroupIds) {
        if (groupId == null || visitedGroupIds.contains(groupId)) {
            return null;
        }
        visitedGroupIds.add(groupId);

        List<GroupMember> members = [
            SELECT UserOrGroupId
            FROM GroupMember
            WHERE GroupId = :groupId
            ORDER BY UserOrGroupId
        ];

        for (GroupMember member : members) {
            if (member.UserOrGroupId.getSObjectType() == User.SObjectType) {
                return member.UserOrGroupId;
            }
        }
        for (GroupMember member : members) {
            if (member.UserOrGroupId.getSObjectType() == Group.SObjectType) {
                Id nestedApproverId = resolveFirstUserMember(member.UserOrGroupId, visitedGroupIds);
                if (nestedApproverId != null) {
                    return nestedApproverId;
                }
            }
        }
        return null;
    }
}
