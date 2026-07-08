public with sharing class BookController {

    @AuraEnabled(cacheable=true)
    public static List<Book__c> getBooks() {
        return [
            SELECT Id, Name, Price__c, PublishedDate__c, Status__c,
                   AuthorEmail__c, Rating__c, Summary__c, Cost__c
            FROM Book__c
            ORDER BY CreatedDate DESC
        ];
    }

    @AuraEnabled(cacheable=true)
    public static List<Book__c> searchByAuthorEmail(String email) {
        return BookService.searchByAuthorEmail(email);
    }

    @AuraEnabled(cacheable=true)
    public static List<Book__c> getPublishedBooks() {
        return BookService.getPublishedBooks();
    }

    @AuraEnabled(cacheable=true)
    public static Map<String, Integer> getBookCountByStatus() {
        return BookService.getBookCountByStatus();
    }

    @AuraEnabled
    public static void applyDiscount(List<Id> bookIds, Decimal discountPercent) {
        BookService.applyDiscount(new Set<Id>(bookIds), discountPercent);
    }

    @AuraEnabled
    public static Integer deleteByStatus(String status) {
        return BookService.deleteByStatus(status);
    }
}
