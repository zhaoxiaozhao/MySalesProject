public without sharing class BookService {

    public static List<Book__c> searchByAuthorEmail(String email) {
        return [
            SELECT Id, Name, Price__c, PublishedDate__c, Status__c, AuthorEmail__c, Summary__c
            FROM Book__c
            WHERE AuthorEmail__c = :email
            ORDER BY Name
        ];
    }

    public static List<Book__c> getPublishedBooks() {
        return [
            SELECT Id, Name, Price__c, PublishedDate__c, Rating__c, Summary__c
            FROM Book__c
            WHERE Status__c = 'Published'
            ORDER BY PublishedDate__c DESC
        ];
    }

    public static Map<String, Integer> getBookCountByStatus() {
        Map<String, Integer> result = new Map<String, Integer>();
        for (AggregateResult ar : [
            SELECT Status__c, COUNT(Id) cnt
            FROM Book__c
            GROUP BY Status__c
        ]) {
            result.put((String) ar.get('Status__c'), (Integer) ar.get('cnt'));
        }
        return result;
    }

    public static void applyDiscount(Set<Id> bookIds, Decimal discountPercent) {
        if (discountPercent == null || discountPercent <= 0 || discountPercent > 100) {
            throw new IllegalArgumentException('Discount must be between 1 and 100');
        }
        List<Book__c> books = [
            SELECT Id, Price__c
            FROM Book__c
            WHERE Id IN :bookIds AND Price__c != NULL
        ];
        for (Book__c book : books) {
            book.Price__c = book.Price__c * (1 - discountPercent / 100);
        }
        update books;
    }

    public static Integer deleteByStatus(String status) {
        List<Book__c> books = [SELECT Id FROM Book__c WHERE Status__c = :status];
        if (!books.isEmpty()) {
            delete books;
        }
        return books.size();
    }
}
