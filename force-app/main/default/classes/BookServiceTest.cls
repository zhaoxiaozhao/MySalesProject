@IsTest
private class BookServiceTest {

    static List<Book__c> createTestBooks() {
        List<Book__c> books = new List<Book__c>();
        books.add(new Book__c(
            Name = 'Test Book 1',
            Price__c = 100,
            Status__c = 'Published',
            AuthorEmail__c = 'author@test.com',
            Rating__c = 4.5
        ));
        books.add(new Book__c(
            Name = 'Test Book 2',
            Price__c = 50,
            Status__c = 'Draft',
            AuthorEmail__c = 'author@test.com'
        ));
        books.add(new Book__c(
            Name = 'Test Book 3',
            Price__c = 200,
            Status__c = 'Published',
            Rating__c = 3.0
        ));
        insert books;
        return books;
    }

    @IsTest
    static void testSearchByAuthorEmail() {
        createTestBooks();
        List<Book__c> results = BookService.searchByAuthorEmail('author@test.com');
        Assert.areEqual(2, results.size(), 'Should find 2 books by this email');
    }

    @IsTest
    static void testGetPublishedBooks() {
        createTestBooks();
        List<Book__c> results = BookService.getPublishedBooks();
        Assert.areEqual(2, results.size(), 'Should find 2 published books');
    }

    @IsTest
    static void testGetBookCountByStatus() {
        createTestBooks();
        Map<String, Integer> counts = BookService.getBookCountByStatus();
        Assert.areEqual(2, counts.get('Published'), 'Should have 2 Published books');
        Assert.areEqual(1, counts.get('Draft'), 'Should have 1 Draft book');
    }

    @IsTest
    static void testApplyDiscount() {
        createTestBooks();
        Book__c book = [SELECT Id, Price__c FROM Book__c WHERE Name = 'Test Book 1' LIMIT 1];
        Set<Id> ids = new Set<Id>{ book.Id };
        BookService.applyDiscount(ids, 10);
        Book__c updated = [SELECT Price__c FROM Book__c WHERE Id = :book.Id];
        Assert.areEqual(90, updated.Price__c, 'Price should be 90 after 10% discount');
    }

    @IsTest
    static void testApplyDiscountInvalidPercent() {
        try {
            BookService.applyDiscount(new Set<Id>{ UserInfo.getUserId() }, 200);
            Assert.fail('Should have thrown an exception');
        } catch (IllegalArgumentException e) {
            Assert.isTrue(e.getMessage().contains('Discount must be between 1 and 100'));
        }
    }

    @IsTest
    static void testDeleteByStatus() {
        createTestBooks();
        Integer deleted = BookService.deleteByStatus('Draft');
        Assert.areEqual(1, deleted, 'Should delete 1 Draft book');
        List<Book__c> remaining = [SELECT Id FROM Book__c];
        Assert.areEqual(2, remaining.size(), 'Should have 2 books remaining');
    }
}
