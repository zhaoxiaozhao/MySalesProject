@IsTest
private class TestRestrictContactByName {

    @IsTest
    static void testAllowValidInsert() {
        Contact contactRecord = new Contact(LastName = 'ValidName');

        Test.startTest();
        insert contactRecord;
        Test.stopTest();

        Contact savedContact = [
            SELECT Id, LastName
            FROM Contact
            WHERE Id = :contactRecord.Id
        ];
        Assert.areEqual('ValidName', savedContact.LastName, '合法姓氏应允许插入');
    }

    @IsTest
    static void testBlockInvalidInsertAndUpdate() {
        Contact validContact = new Contact(LastName = 'OriginalName');
        insert validContact;

        try {
            insert new Contact(LastName = 'INVALIDNAME');
            Assert.fail('插入 INVALIDNAME 时应抛出异常');
        } catch (DmlException e) {
            Assert.isTrue(
                e.getMessage().contains('The Last Name "INVALIDNAME" is not allowed for DML'),
                '插入场景应返回预期错误消息'
            );
        }

        validContact.LastName = 'INVALIDNAME';
        try {
            update validContact;
            Assert.fail('更新为 INVALIDNAME 时应抛出异常');
        } catch (DmlException e) {
            Assert.isTrue(
                e.getMessage().contains('The Last Name "INVALIDNAME" is not allowed for DML'),
                '更新场景应返回预期错误消息'
            );
        }
    }
}
