import { LightningElement } from 'lwc';
import getBooks from '@salesforce/apex/BookController.getBooks';
import searchByAuthorEmail from '@salesforce/apex/BookController.searchByAuthorEmail';
import getPublishedBooks from '@salesforce/apex/BookController.getPublishedBooks';
import getBookCountByStatus from '@salesforce/apex/BookController.getBookCountByStatus';
import applyDiscount from '@salesforce/apex/BookController.applyDiscount';
import deleteByStatus from '@salesforce/apex/BookController.deleteByStatus';

const COLUMNS = [
    { label: 'Book Name', fieldName: 'Name', type: 'text' },
    { label: 'Price', fieldName: 'Price__c', type: 'currency' },
    { label: 'Published Date', fieldName: 'PublishedDate__c', type: 'date' },
    { label: 'Status', fieldName: 'Status__c', type: 'text' },
    { label: 'Rating', fieldName: 'Rating__c', type: 'number' },
    { label: 'Author Email', fieldName: 'AuthorEmail__c', type: 'email' },
];

export default class BookManager extends LightningElement {
    columns = COLUMNS;
    books = [];
    selectedIds = new Set();
    searchEmail = '';
    discountPercent = 10;
    deleteStatus = 'Draft';
    stats;
    error;
    success;
    isLoading = false;

    get isSearchDisabled() {
        return !this.searchEmail || this.isLoading;
    }

    get isActionDisabled() {
        return this.selectedIds.size === 0 || this.isLoading;
    }

    get deleteButtonLabel() {
        return 'Delete ' + this.deleteStatus;
    }

    get statItems() {
        if (!this.stats) return [];
        return Object.keys(this.stats).map((key) => ({
            key,
            count: this.stats[key],
        }));
    }

    connectedCallback() {
        this.loadBooks();
        this.loadStats();
    }

    handleEmailChange(event) {
        this.searchEmail = event.target.value;
    }

    handleDiscountChange(event) {
        this.discountPercent = event.target.value;
    }

    handleSelection(event) {
        this.selectedIds = new Set(event.detail.selectedRows.map((r) => r.Id));
    }

    loadBooks() {
        this.isLoading = true;
        this.error = null;
        this.success = null;
        getBooks()
            .then((data) => {
                this.books = data;
            })
            .catch((err) => {
                this.error = 'Failed to load books: ' + err.body.message;
            })
            .finally(() => {
                this.isLoading = false;
            });
    }

    searchByEmail() {
        this.isLoading = true;
        this.error = null;
        this.success = null;
        searchByAuthorEmail({ email: this.searchEmail })
            .then((data) => {
                this.books = data;
                if (data.length === 0) {
                    this.success = 'No books found for this email.';
                }
            })
            .catch((err) => {
                this.error = 'Search failed: ' + err.body.message;
            })
            .finally(() => {
                this.isLoading = false;
            });
    }

    loadPublished() {
        this.isLoading = true;
        this.error = null;
        this.success = null;
        getPublishedBooks()
            .then((data) => {
                this.books = data;
                this.success = 'Showing ' + data.length + ' published book(s).';
            })
            .catch((err) => {
                this.error = 'Failed to load published books: ' + err.body.message;
            })
            .finally(() => {
                this.isLoading = false;
            });
    }

    loadStats() {
        getBookCountByStatus()
            .then((data) => {
                this.stats = data;
            })
            .catch(() => {
                this.stats = null;
            });
    }

    applyDiscount() {
        if (this.discountPercent <= 0 || this.discountPercent > 100) {
            this.error = 'Discount must be between 1 and 100.';
            return;
        }
        this.isLoading = true;
        this.error = null;
        this.success = null;
        applyDiscount({
            bookIds: Array.from(this.selectedIds),
            discountPercent: Number(this.discountPercent),
        })
            .then(() => {
                this.success = 'Discount applied successfully!';
                this.loadBooks();
                this.loadStats();
            })
            .catch((err) => {
                this.error = 'Failed to apply discount: ' + err.body.message;
            })
            .finally(() => {
                this.isLoading = false;
            });
    }

    deleteByStatus() {
        if (!this.deleteStatus) return;
        this.isLoading = true;
        this.error = null;
        this.success = null;
        deleteByStatus({ status: this.deleteStatus })
            .then((count) => {
                this.success = 'Deleted ' + count + ' book(s) with status "' + this.deleteStatus + '".';
                this.loadBooks();
                this.loadStats();
            })
            .catch((err) => {
                this.error = 'Failed to delete: ' + err.body.message;
            })
            .finally(() => {
                this.isLoading = false;
            });
    }
}
