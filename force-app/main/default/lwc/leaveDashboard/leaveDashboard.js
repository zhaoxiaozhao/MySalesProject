import { LightningElement, track } from 'lwc';
import getCalendar from '@salesforce/apex/LeaveDashboardController.getCalendar';

const WEEKDAY_LABELS = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];
const STATUS_CLASS_MAP = {
    Approved: 'entry entry-approved',
    Submitted: 'entry entry-submitted',
    Pending_Manager_Approval: 'entry entry-manager',
    Pending_HR_Approval: 'entry entry-hr',
};

export default class LeaveDashboard extends LightningElement {
    weekdayLabels = WEEKDAY_LABELS;
    @track calendarCells = [];
    @track calendarEntries = [];
    @track scopeLabel = 'My Calendar';
    @track titleLabel = '';
    isLoading = false;
    error;
    currentMonthDate = this.toMonthStart(new Date());

    connectedCallback() {
        this.loadCalendar();
    }

    get hasCalendarCells() {
        return this.calendarCells.length > 0;
    }

    get hasError() {
        return !!this.error;
    }

    previousMonth() {
        this.currentMonthDate = new Date(
            this.currentMonthDate.getFullYear(),
            this.currentMonthDate.getMonth() - 1,
            1
        );
        this.loadCalendar();
    }

    nextMonth() {
        this.currentMonthDate = new Date(
            this.currentMonthDate.getFullYear(),
            this.currentMonthDate.getMonth() + 1,
            1
        );
        this.loadCalendar();
    }

    loadCalendar() {
        this.isLoading = true;
        this.error = null;

        getCalendar({ referenceDate: this.toIsoDate(this.currentMonthDate) })
            .then((payload) => {
                const monthStart = payload && payload.monthStartDate
                    ? this.fromIsoDate(payload.monthStartDate)
                    : this.toMonthStart(this.currentMonthDate);
                this.currentMonthDate = monthStart;
                this.scopeLabel = this.resolveScopeLabel(payload ? payload.scopeLabel : null);
                this.titleLabel = monthStart.toLocaleDateString('en-US', {
                    year: 'numeric',
                    month: 'long',
                });

                const entries = (payload && payload.entries ? payload.entries : []).map((entry) => ({
                    ...entry,
                    displayName: entry.employeeName || 'Unknown',
                    initials: this.buildInitials(entry.employeeName),
                    photoUrl: entry.employeePhotoUrl,
                    entryClass: STATUS_CLASS_MAP[entry.status] || 'entry',
                }));
                this.calendarEntries = entries;
                this.calendarCells = this.buildCalendarCells(monthStart, entries);
            })
            .catch((error) => {
                this.error = this.reduceError(error);
                this.calendarCells = [];
            })
            .finally(() => {
                this.isLoading = false;
            });
    }

    buildCalendarCells(monthStartDate, entries) {
        const monthStartIso = this.toIsoDate(monthStartDate);
        const gridStartDate = new Date(monthStartDate);
        gridStartDate.setDate(monthStartDate.getDate() - monthStartDate.getDay());

        const todayIso = this.toIsoDate(new Date());
        const cells = [];
        for (let index = 0; index < 42; index += 1) {
            const cellDate = new Date(gridStartDate);
            cellDate.setDate(gridStartDate.getDate() + index);
            const cellIsoDate = this.toIsoDate(cellDate);
            const matchingEntries = entries.filter((entry) =>
                entry.startDate <= cellIsoDate && entry.endDate >= cellIsoDate
            );

            cells.push({
                key: cellIsoDate,
                isoDate: cellIsoDate,
                dayNumber: cellDate.getDate(),
                isCurrentMonth: cellDate.getMonth() === monthStartDate.getMonth(),
                isToday: cellIsoDate === todayIso,
                cellClass: this.buildCellClass(cellDate, monthStartDate, todayIso),
                entries: matchingEntries.slice(0, 4),
                moreCount: Math.max(matchingEntries.length - 4, 0),
                isFirstOfMonth: cellIsoDate === monthStartIso,
            });
        }

        return cells;
    }

    buildCellClass(cellDate, monthStartDate, todayIso) {
        const classes = ['calendar-cell'];
        if (cellDate.getMonth() !== monthStartDate.getMonth()) {
            classes.push('calendar-cell-muted');
        }
        if (this.toIsoDate(cellDate) === todayIso) {
            classes.push('calendar-cell-today');
        }
        return classes.join(' ');
    }

    resolveScopeLabel(scopeLabel) {
        if (scopeLabel === 'ALL') {
            return 'All Leave';
        }
        if (scopeLabel === 'TEAM') {
            return 'Team Leave';
        }
        return 'My Leave';
    }

    buildInitials(name) {
        if (!name) {
            return '?';
        }
        const parts = name.trim().split(/\s+/).filter(Boolean);
        if (parts.length === 1) {
            return parts[0].substring(0, 1).toUpperCase();
        }
        return (parts[0].substring(0, 1) + parts[parts.length - 1].substring(0, 1)).toUpperCase();
    }

    toMonthStart(dateValue) {
        return new Date(dateValue.getFullYear(), dateValue.getMonth(), 1);
    }

    toIsoDate(dateValue) {
        const yearValue = dateValue.getFullYear();
        const monthValue = String(dateValue.getMonth() + 1).padStart(2, '0');
        const dayValue = String(dateValue.getDate()).padStart(2, '0');
        return `${yearValue}-${monthValue}-${dayValue}`;
    }

    fromIsoDate(isoDateValue) {
        const [yearValue, monthValue, dayValue] = isoDateValue.split('-').map((item) => parseInt(item, 10));
        return new Date(yearValue, monthValue - 1, dayValue);
    }

    reduceError(error) {
        if (!error) {
            return 'Unknown error';
        }
        if (error.body && error.body.message) {
            return error.body.message;
        }
        if (error.message) {
            return error.message;
        }
        return 'Unknown error';
    }
}
