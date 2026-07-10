import { LightningElement } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getUserRoles from '@salesforce/apex/LeaveHomeController.getUserRoles';
import getMyBalance from '@salesforce/apex/LeaveHomeController.getMyBalance';
import getMyRequests from '@salesforce/apex/LeaveHomeController.getMyRequests';
import getPendingApprovals from '@salesforce/apex/LeaveHomeController.getPendingApprovals';
import getHrPendingApprovals from '@salesforce/apex/LeaveHomeController.getHrPendingApprovals';
import getAvailableLeaveTypes from '@salesforce/apex/LeaveHomeController.getAvailableLeaveTypes';
import createLeaveRequest from '@salesforce/apex/LeaveHomeController.createLeaveRequest';
import submitLeaveAction from '@salesforce/apex/LeaveHomeController.submitLeaveAction';
import cancelLeaveAction from '@salesforce/apex/LeaveHomeController.cancelLeaveAction';
import approveLeaveAction from '@salesforce/apex/LeaveHomeController.approveLeaveAction';
import rejectLeaveAction from '@salesforce/apex/LeaveHomeController.rejectLeaveAction';

const FULL_DAY_TIME_SLOT = 'Full_Day';
const MORNING_TIME_SLOT = 'Morning';
const AFTERNOON_TIME_SLOT = 'Afternoon';
const TIME_SLOT_OPTIONS = [
    { label: 'Full Day', value: FULL_DAY_TIME_SLOT },
    { label: 'Morning', value: MORNING_TIME_SLOT },
    { label: 'Afternoon', value: AFTERNOON_TIME_SLOT },
];

const EMPLOYEE_COLUMNS = [
    { label: 'Number', fieldName: 'detailUrl', type: 'url',
        typeAttributes: { label: { fieldName: 'Name' }, target: '_self' } },
    { label: 'Type', fieldName: 'Leave_Type_Name__c', type: 'text' },
    { label: 'Start', fieldName: 'Start_Date__c', type: 'date' },
    { label: 'End', fieldName: 'End_Date__c', type: 'date' },
    { label: 'Time Slot', fieldName: 'TimeSlotLabel', type: 'text' },
    { label: 'Days', fieldName: 'Days__c', type: 'number' },
    { label: 'Status', fieldName: 'Status__c', type: 'text' },
    {
        type: 'button',
        fixedWidth: 100,
        typeAttributes: {
            label: 'Submit',
            name: 'submit',
            variant: 'brand',
            disabled: { fieldName: 'submitDisabled' }
        }
    },
    {
        type: 'button',
        fixedWidth: 100,
        typeAttributes: {
            label: 'Cancel',
            name: 'cancel',
            variant: 'destructive-text',
            disabled: { fieldName: 'cancelDisabled' }
        }
    },
];

const MANAGER_COLUMNS = [
    { label: 'Number', fieldName: 'detailUrl', type: 'url',
        typeAttributes: { label: { fieldName: 'Name' }, target: '_self' } },
    { label: 'Employee', fieldName: 'EmployeeName', type: 'text' },
    { label: 'Type', fieldName: 'Leave_Type_Name__c', type: 'text' },
    { label: 'Start', fieldName: 'Start_Date__c', type: 'date' },
    { label: 'End', fieldName: 'End_Date__c', type: 'date' },
    { label: 'Time Slot', fieldName: 'TimeSlotLabel', type: 'text' },
    { label: 'Days', fieldName: 'Days__c', type: 'number' },
    { label: 'Status', fieldName: 'Status__c', type: 'text' },
    {
        type: 'button',
        fixedWidth: 100,
        typeAttributes: {
            label: 'Approve',
            name: 'approve',
            variant: 'brand',
            disabled: { fieldName: 'approveDisabled' }
        }
    },
    {
        type: 'button',
        fixedWidth: 100,
        typeAttributes: {
            label: 'Reject',
            name: 'reject',
            variant: 'destructive-text',
            disabled: { fieldName: 'rejectDisabled' }
        }
    },
];

const HR_PENDING_COLUMNS = [
    { label: 'Number', fieldName: 'detailUrl', type: 'url',
        typeAttributes: { label: { fieldName: 'Name' }, target: '_self' } },
    { label: 'Employee', fieldName: 'EmployeeName', type: 'text' },
    { label: 'Type', fieldName: 'Leave_Type_Name__c', type: 'text' },
    { label: 'Start', fieldName: 'Start_Date__c', type: 'date' },
    { label: 'End', fieldName: 'End_Date__c', type: 'date' },
    { label: 'Time Slot', fieldName: 'TimeSlotLabel', type: 'text' },
    { label: 'Days', fieldName: 'Days__c', type: 'number' },
    { label: 'Status', fieldName: 'Status__c', type: 'text' },
    {
        type: 'button',
        fixedWidth: 100,
        typeAttributes: {
            label: 'Approve',
            name: 'approve',
            variant: 'brand',
            disabled: { fieldName: 'approveDisabled' }
        }
    },
    {
        type: 'button',
        fixedWidth: 100,
        typeAttributes: {
            label: 'Reject',
            name: 'reject',
            variant: 'destructive-text',
            disabled: { fieldName: 'rejectDisabled' }
        }
    },
];

export default class LeaveHome extends LightningElement {
    employeeColumns = EMPLOYEE_COLUMNS;
    managerColumns = MANAGER_COLUMNS;
    hrPendingColumns = HR_PENDING_COLUMNS;
    roles = {};
    balance;
    myRequests = [];
    pendingApprovals = [];
    hrPendingApprovals = [];
    error;
    isLoading = false;
    isCreateModalOpen = false;
    leaveTypeOptions = [];
    timeSlotOptions = TIME_SLOT_OPTIONS;
    newRequestForm = this.buildEmptyRequestForm();

    connectedCallback() {
        this.loadData();
        this.loadLeaveTypeOptions();
    }

    loadData() {
        return getUserRoles()
            .then((r) => {
                this.roles = r;
                return Promise.all([
                    this.loadEmployeeData(),
                    r.isManager ? this.loadManagerData() : Promise.resolve(),
                    r.isHR ? this.loadHRData() : Promise.resolve(),
                ]);
            })
            .catch((err) => { this.error = this.reduceError(err); });
    }

    loadLeaveTypeOptions() {
        getAvailableLeaveTypes()
            .then((data) => {
                this.leaveTypeOptions = data.map((item) => ({
                    label: item.label,
                    value: item.definitionId,
                    description: item.typeCode,
                }));
            })
            .catch((err) => { this.error = this.reduceError(err); });
    }

    loadEmployeeData() {
        return Promise.all([getMyBalance(), getMyRequests()])
            .then(([balanceData, requestData]) => {
                this.balance = balanceData;
                const data = requestData || [];
                this.myRequests = data.map((r) => this.mapEmployeeRequest(r));
            })
            .catch((err) => { this.error = this.reduceError(err); });
    }

    loadManagerData() {
        return getPendingApprovals()
            .then((data) => {
                const rows = data || [];
                this.pendingApprovals = rows.map((r) => this.mapApprovalRequest(r, 'Pending_Manager_Approval'));
            })
            .catch((err) => { this.error = this.reduceError(err); });
    }

    loadHRData() {
        return getHrPendingApprovals()
            .then((hrPendingData) => {
                const pendingRows = hrPendingData || [];
                this.hrPendingApprovals = pendingRows.map((r) => this.mapApprovalRequest(r, 'Pending_HR_Approval'));
            })
            .catch((err) => { this.error = this.reduceError(err); });
    }

    newRequest() {
        this.error = null;
        this.newRequestForm = this.buildEmptyRequestForm();
        this.isCreateModalOpen = true;
    }

    closeCreateModal() {
        this.isCreateModalOpen = false;
    }

    handleCreateFieldChange(event) {
        const { name, value } = event.target;
        this.newRequestForm = {
            ...this.newRequestForm,
            [name]: value,
        };
    }

    saveRequest() {
        this.isLoading = true;
        this.error = null;
        createLeaveRequest({
            leaveTypeDefinitionId: this.newRequestForm.leaveTypeDefinitionId,
            startDate: this.newRequestForm.startDate,
            endDate: this.newRequestForm.endDate,
            startTimeSlot: this.newRequestForm.startTimeSlot,
            endTimeSlot: this.newRequestForm.endTimeSlot,
            reason: this.newRequestForm.reason,
        })
            .then(() => {
                this.showToast('Success', 'Draft leave request created successfully.', 'success');
                this.isCreateModalOpen = false;
                this.newRequestForm = this.buildEmptyRequestForm();
                return this.loadEmployeeData();
            })
            .catch((err) => {
                this.error = this.reduceError(err);
                this.showToast('Error', this.error, 'error');
            })
            .finally(() => {
                this.isLoading = false;
            });
    }

    handleMyRequestRowAction(event) {
        const { action, row } = event.detail;
        if (action.name === 'submit') {
            this.runAction(
                submitLeaveAction({ leaveRequestId: row.Id }),
                'Leave request submitted successfully.'
            );
        } else if (action.name === 'cancel') {
            this.runAction(
                cancelLeaveAction({ leaveRequestId: row.Id }),
                'Leave request cancelled successfully.'
            );
        }
    }

    handleManagerRowAction(event) {
        const { action, row } = event.detail;
        if (action.name === 'approve') {
            this.runAction(
                approveLeaveAction({ leaveRequestId: row.Id }),
                'Leave request approved successfully.'
            );
        } else if (action.name === 'reject') {
            this.runAction(
                rejectLeaveAction({ leaveRequestId: row.Id }),
                'Leave request rejected successfully.'
            );
        }
    }

    handleHrRowAction(event) {
        this.handleManagerRowAction(event);
    }

    runAction(actionPromise, successMessage) {
        this.isLoading = true;
        this.error = null;
        actionPromise
            .then(() => {
                this.showToast('Success', successMessage, 'success');
                return this.loadData();
            })
            .catch((err) => {
                this.error = this.reduceError(err);
                this.showToast('Error', this.error, 'error');
            })
            .finally(() => {
                this.isLoading = false;
            });
    }

    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }

    reduceError(err) {
        if (!err) {
            return 'Unknown error';
        }
        const messages = [];
        if (err.body && Array.isArray(err.body)) {
            messages.push(...err.body.map((item) => item.message));
        }
        if (err.body && err.body.message) {
            messages.push(err.body.message);
        }
        if (err.body && err.body.output) {
            if (Array.isArray(err.body.output.errors)) {
                messages.push(...err.body.output.errors.map((item) => item.message));
            }
            if (Array.isArray(err.body.output.pageErrors)) {
                messages.push(...err.body.output.pageErrors.map((item) => item.message));
            }
            if (err.body.output.fieldErrors) {
                Object.values(err.body.output.fieldErrors).forEach((fieldItems) => {
                    if (Array.isArray(fieldItems)) {
                        messages.push(...fieldItems.map((item) => item.message));
                    }
                });
            }
        }
        if (err.message) {
            messages.push(err.message);
        }

        const normalizedMessages = [...new Set(
            messages
                .filter((message) => typeof message === 'string' && message.trim())
                .map((message) => message.trim())
        )];
        return normalizedMessages.length > 0 ? normalizedMessages.join(', ') : 'Unknown error';
    }

    mapEmployeeRequest(requestRow) {
        const todayValue = new Date().toISOString().slice(0, 10);
        const canCancelApprovedFutureLeave = requestRow.Status__c === 'Approved'
            && requestRow.Start_Date__c
            && requestRow.Start_Date__c > todayValue;
        return {
            ...requestRow,
            Leave_Type_Name__c: this.resolveLeaveTypeName(requestRow),
            TimeSlotLabel: this.resolveTimeSlotLabel(requestRow),
            detailUrl: '/lightning/r/Leave_Request__c/' + requestRow.Id + '/view',
            submitDisabled: requestRow.Status__c !== 'Draft',
            cancelDisabled: !['Draft', 'Submitted', 'Pending_Manager_Approval', 'Pending_HR_Approval']
                .includes(requestRow.Status__c) && !canCancelApprovedFutureLeave,
        };
    }

    mapApprovalRequest(requestRow, actionableStatus) {
        const actionableStatuses = actionableStatus === 'Pending_Manager_Approval'
            ? ['Submitted', 'Pending_Manager_Approval']
            : [actionableStatus];
        return {
            ...requestRow,
            EmployeeName: requestRow.Employee__r ? requestRow.Employee__r.Name : '',
            Leave_Type_Name__c: this.resolveLeaveTypeName(requestRow),
            TimeSlotLabel: this.resolveTimeSlotLabel(requestRow),
            detailUrl: '/lightning/r/Leave_Request__c/' + requestRow.Id + '/view',
            approveDisabled: !actionableStatuses.includes(requestRow.Status__c),
            rejectDisabled: !actionableStatuses.includes(requestRow.Status__c),
        };
    }

    resolveLeaveTypeName(requestRow) {
        if (requestRow.Leave_Type_Name__c) {
            return requestRow.Leave_Type_Name__c;
        }
        if (requestRow.Leave_Type_Definition__r && requestRow.Leave_Type_Definition__r.Name) {
            return requestRow.Leave_Type_Definition__r.Name;
        }
        return '';
    }

    resolveTimeSlotLabel(requestRow) {
        const startSlot = requestRow.Start_Time_Slot__c || FULL_DAY_TIME_SLOT;
        const endSlot = requestRow.End_Time_Slot__c || FULL_DAY_TIME_SLOT;
        if (requestRow.Start_Date__c && requestRow.End_Date__c && requestRow.Start_Date__c === requestRow.End_Date__c) {
            if (startSlot === endSlot && startSlot !== FULL_DAY_TIME_SLOT) {
                return this.formatTimeSlot(startSlot);
            }
            return startSlot === FULL_DAY_TIME_SLOT && endSlot === FULL_DAY_TIME_SLOT
                ? 'Full Day'
                : `${this.formatTimeSlot(startSlot)} - ${this.formatTimeSlot(endSlot)}`;
        }
        if (startSlot === FULL_DAY_TIME_SLOT && endSlot === FULL_DAY_TIME_SLOT) {
            return 'Full Day';
        }
        return `${this.formatTimeSlot(startSlot)} start / ${this.formatTimeSlot(endSlot)} end`;
    }

    formatTimeSlot(timeSlot) {
        if (timeSlot === MORNING_TIME_SLOT) {
            return 'Morning';
        }
        if (timeSlot === AFTERNOON_TIME_SLOT) {
            return 'Afternoon';
        }
        return 'Full Day';
    }

    get hasMyRequests() {
        return this.myRequests.length > 0;
    }

    get hasPendingApprovals() {
        return this.pendingApprovals.length > 0;
    }

    get hasHrPendingApprovals() {
        return this.hrPendingApprovals.length > 0;
    }

    buildEmptyRequestForm() {
        return {
            leaveTypeDefinitionId: null,
            startDate: null,
            endDate: null,
            startTimeSlot: FULL_DAY_TIME_SLOT,
            endTimeSlot: FULL_DAY_TIME_SLOT,
            reason: '',
        };
    }
}
