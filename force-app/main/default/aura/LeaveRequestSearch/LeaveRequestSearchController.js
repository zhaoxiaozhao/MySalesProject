({
    doInit: function(component, event, helper) {
        helper.initialize(component);
    },

    handleSearch: function(component, event, helper) {
        helper.search(component);
    },

    handleReset: function(component, event, helper) {
        component.set('v.keyword', '');
        component.set('v.employeeKeyword', '');
        component.set('v.status', '');
        component.set('v.scope', 'MY');
        component.set('v.leaveDateFrom', null);
        component.set('v.leaveDateTo', null);
        component.set('v.errorMessage', null);
        helper.search(component);
    }
})
