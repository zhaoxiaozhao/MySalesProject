import { LightningElement } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import getUserRoles from '@salesforce/apex/LeaveHomeController.getUserRoles';
import getMyBalance from '@salesforce/apex/LeaveHomeController.getMyBalance';
import getMyRequests from '@salesforce/apex/LeaveHomeController.getMyRequests';
import getPendingApprovals from '@salesforce/apex/LeaveHomeController.getPendingApprovals';
import getAllRequests from '@salesforce/apex/LeaveHomeController.getAllRequests';
import getAllBalances from '@salesforce/apex/LeaveHomeController.getAllBalances';

const EMPLOYEE_COLUMNS = [
    { label: 'Number', fieldName: 'detailUrl', type: 'url',
        typeAttributes: { label: { fieldName: 'Name' }, target: '_self' } },
    { label: 'Type', fieldName: 'Leave_Type__c', type: 'text' },
    { label: 'Start', fieldName: 'Start_Date__c', type: 'date' },
    { label: 'End', fieldName: 'End_Date__c', type: 'date' },
    { label: 'Days', fieldName: 'Days__c', type: 'number' },
    { label: 'Status', fieldName: 'Status__c', type: 'text' },
];

const MANAGER_COLUMNS = [
    { label: 'Number', fieldName: 'detailUrl', type: 'url',
        typeAttributes: { label: { fieldName: 'Name' }, target: '_self' } },
    { label: 'Employee', fieldName: 'EmployeeName', type: 'text' },
    { label: 'Type', fieldName: 'Leave_Type__c', type: 'text' },
    { label: 'Start', fieldName: 'Start_Date__c', type: 'date' },
    { label: 'End', fieldName: 'End_Date__c', type: 'date' },
    { label: 'Days', fieldName: 'Days__c', type: 'number' },
    { label: 'Status', fieldName: 'Status__c', type: 'text' },
];

const HR_COLUMNS = [
    { label: 'Number', fieldName: 'detailUrl', type: 'url',
        typeAttributes: { label: { fieldName: 'Name' }, target: '_self' } },
    { label: 'Employee', fieldName: 'EmployeeName', type: 'text' },
    { label: 'Type', fieldName: 'Leave_Type__c', type: 'text' },
    { label: 'Start', fieldName: 'Start_Date__c', type: 'date' },
    { label: 'End', fieldName: 'End_Date__c', type: 'date' },
    { label: 'Days', fieldName: 'Days__c', type: 'number' },
    { label: 'Status', fieldName: 'Status__c', type: 'text' },
];

const BALANCE_COLUMNS = [
    { label: 'Number', fieldName: 'Name', type: 'text' },
    { label: 'User', fieldName: 'UserName', type: 'text' },
    { label: 'Year', fieldName: 'Year__c', type: 'number' },
    { label: 'Annual Total', fieldName: 'Annual_Total_Available__c', type: 'number' },
    { label: 'Carryover', fieldName: 'Carryover_Annual_Leave__c', type: 'number' },
    { label: 'Carryover Expiry', fieldName: 'Carryover_Expiry_Date__c', type: 'date' },
    { label: 'Sick', fieldName: 'Sick_Leave__c', type: 'number' },
    { label: 'Personal', fieldName: 'Personal_Leave__c', type: 'number' },
];

export default class LeaveHome extends NavigationMixin(LightningElement) {
    employeeColumns = EMPLOYEE_COLUMNS;
    managerColumns = MANAGER_COLUMNS;
    hrColumns = HR_COLUMNS;
    balanceColumns = BALANCE_COLUMNS;
    roles = {};
    balance;
    myRequests;
    pendingApprovals;
    allRequests;
    allBalances;
    error;

    connectedCallback() {
        this.loadData();
    }

    loadData() {
        getUserRoles()
            .then((r) => {
                this.roles = r;
                this.loadEmployeeData();
                if (r.isManager) this.loadManagerData();
                if (r.isHR) this.loadHRData();
            })
            .catch((err) => { this.error = err.body.message; });
    }

    loadEmployeeData() {
        getMyBalance()
            .then((data) => { this.balance = data; })
            .catch((err) => { this.error = err.body.message; });

        getMyRequests()
            .then((data) => {
                this.myRequests = data.map((r) => ({
                    ...r, detailUrl: '/lightning/r/Leave_Request__c/' + r.Id + '/view',
                }));
            })
            .catch((err) => { this.error = err.body.message; });
    }

    loadManagerData() {
        getPendingApprovals()
            .then((data) => {
                this.pendingApprovals = data.map((r) => ({
                    ...r,
                    EmployeeName: r.Employee__r ? r.Employee__r.Name : '',
                    detailUrl: '/lightning/r/Leave_Request__c/' + r.Id + '/view',
                }));
            })
            .catch((err) => { this.error = err.body.message; });
    }

    loadHRData() {
        getAllRequests()
            .then((data) => {
                this.allRequests = data.map((r) => ({
                    ...r,
                    EmployeeName: r.Employee__r ? r.Employee__r.Name : '',
                    detailUrl: '/lightning/r/Leave_Request__c/' + r.Id + '/view',
                }));
            })
            .catch((err) => { this.error = err.body.message; });

        getAllBalances()
            .then((data) => {
                this.allBalances = data.map((b) => ({
                    ...b, UserName: b.User__r ? b.User__r.Name : '',
                }));
            })
            .catch((err) => { this.error = err.body.message; });
    }

    newRequest() {
        this[NavigationMixin.Navigate]({
            type: 'standard__objectPage',
            attributes: {
                objectApiName: 'Leave_Request__c',
                actionName: 'new',
            },
        });
    }
}
