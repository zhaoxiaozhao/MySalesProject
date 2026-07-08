public without sharing class LeaveApprovalRoutingService {

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
            decision.nextStatus = 'Pending_Manager_Approval';
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
                decision.nextStatus = 'Pending_Manager_Approval';
                decision.approvalModeSnapshot = 'Manager Then HR';
                decision.approvalTargetSnapshot = getHrTarget(policy);
                return decision;
            }
        }

        validateManagerAvailability(managerId);
        decision.nextStatus = 'Pending_Manager_Approval';
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
            requestRecord.Status__c == 'Pending_Manager_Approval') {
            return requestRecord.Manager__c;
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
            if (requestRecord.Status__c == 'Pending_Manager_Approval') {
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
}
