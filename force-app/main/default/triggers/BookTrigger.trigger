trigger BookTrigger on Book__c (before insert, before update, after insert, after update) {

    if (Trigger.isBefore && Trigger.isInsert) {
        for (Book__c book : Trigger.new) {
            if (String.isBlank(book.Name)) {
                book.Name = 'Book ' + System.now().format('yyyyMMddHHmmss');
            }
        }
    }

    if (Trigger.isBefore && (Trigger.isInsert || Trigger.isUpdate)) {
        for (Book__c book : Trigger.new) {
            if (book.Price__c != null && book.Price__c < 0) {
                book.Price__c.addError('Price must be a positive value');
            }
            if (book.Rating__c != null && (book.Rating__c < 0 || book.Rating__c > 5)) {
                book.Rating__c.addError('Rating must be between 0 and 5');
            }
        }
    }

    if (Trigger.isAfter && Trigger.isInsert) {
        List<Book__c> booksWithEmail = new List<Book__c>();
        for (Book__c book : Trigger.new) {
            if (String.isNotBlank(book.AuthorEmail__c)) {
                booksWithEmail.add(book);
            }
        }
        if (!booksWithEmail.isEmpty()) {
            System.debug('Books with author email created: ' + booksWithEmail.size());
        }
    }
}
