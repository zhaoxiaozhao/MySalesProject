({
    initialize: function(component) {
        component.set('v.columns', [
            {
                label: 'Request No',
                fieldName: 'recordUrl',
                type: 'url',
                typeAttributes: {
                    label: { fieldName: 'requestNumber' },
                    target: '_blank'
                }
            },
            { label: 'Employee', fieldName: 'employeeName', type: 'text' },
            { label: 'Manager', fieldName: 'managerName', type: 'text' },
            { label: 'Leave Type', fieldName: 'leaveTypeName', type: 'text' },
            { label: 'Start Date', fieldName: 'startDate', type: 'date' },
            { label: 'End Date', fieldName: 'endDate', type: 'date' },
            { label: 'Days', fieldName: 'days', type: 'number' },
            { label: 'Status', fieldName: 'status', type: 'text' },
            {
                label: 'Submitted Time',
                fieldName: 'submittedTime',
                type: 'date',
                typeAttributes: {
                    year: 'numeric',
                    month: '2-digit',
                    day: '2-digit',
                    hour: '2-digit',
                    minute: '2-digit'
                }
            },
            { label: 'Reason', fieldName: 'reason', type: 'text' }
        ]);

        var action = component.get('c.getSearchContext');
        action.setCallback(this, function(response) {
            var state = response.getState();
            if (state === 'SUCCESS') {
                var context = response.getReturnValue();
                component.set('v.scopeOptions', context.scopeOptions);
                component.set('v.statusOptions', context.statusOptions);
                if (context.scopeOptions && context.scopeOptions.length > 0) {
                    component.set('v.scope', context.scopeOptions[0].value);
                }
                this.search(component);
                return;
            }
            component.set('v.errorMessage', this.reduceError(response.getError()));
        });
        $A.enqueueAction(action);
    },

    search: function(component) {
        component.set('v.isLoading', true);
        component.set('v.errorMessage', null);
        var action = component.get('c.searchLeaveRequests');
        action.setParams({
            keyword: component.get('v.keyword'),
            employeeKeyword: component.get('v.employeeKeyword'),
            status: component.get('v.status'),
            scope: component.get('v.scope'),
            leaveDateFrom: component.get('v.leaveDateFrom'),
            leaveDateTo: component.get('v.leaveDateTo'),
            limitSize: 100
        });
        action.setCallback(this, function(response) {
            component.set('v.isLoading', false);
            var state = response.getState();
            if (state === 'SUCCESS') {
                var rows = response.getReturnValue() || [];
                rows.forEach(function(row) {
                    row.recordUrl = '/' + row.requestId;
                });
                component.set('v.rows', rows);
                component.set('v.resultCount', rows.length);
                return;
            }
            component.set('v.rows', []);
            component.set('v.resultCount', 0);
            component.set('v.errorMessage', this.reduceError(response.getError()));
        });
        $A.enqueueAction(action);
    },

    reduceError: function(errors) {
        if (!errors || !errors.length) {
            return 'Operation failed.';
        }
        var messages = errors
            .map(function(error) {
                return error && error.message ? error.message : null;
            })
            .filter(function(message) {
                return !!message;
            });
        return messages.length > 0 ? messages.join(', ') : 'Operation failed.';
    }
})
