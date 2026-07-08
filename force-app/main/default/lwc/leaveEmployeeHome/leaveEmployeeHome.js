import { LightningElement } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import getMyBalance from '@salesforce/apex/EmployeeLeaveController.getMyBalance';
import getMyRequests from '@salesforce/apex/EmployeeLeaveController.getMyRequests';

const COLUMNS = [
    { label: 'Number', fieldName: 'detailUrl', type: 'url',
        typeAttributes: { label: { fieldName: 'Name' }, target: '_self' } },
    { label: 'Type', fieldName: 'Leave_Type__c', type: 'text' },
    { label: 'Start', fieldName: 'Start_Date__c', type: 'date' },
    { label: 'End', fieldName: 'End_Date__c', type: 'date' },
    { label: 'Days', fieldName: 'Days__c', type: 'number' },
    { label: 'Status', fieldName: 'Status__c', type: 'text' },
];

export default class LeaveEmployeeHome extends NavigationMixin(LightningElement) {
    columns = COLUMNS;
    balance;
    requests;
    error;

    connectedCallback() {
        this.loadData();
    }

    loadData() {
        getMyBalance()
            .then((data) => { this.balance = data; })
            .catch((err) => { this.error = err.body.message; });

        getMyRequests()
            .then((data) => {
                this.requests = data.map((r) => ({
                    ...r,
                    detailUrl: '/lightning/r/Leave_Request__c/' + r.Id + '/view',
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
