public class RandomContactFactory {
    public static List<Contact> generateRandomContacts(Integer recordCount, String commonLastName) {
        List<Contact> contacts = new List<Contact>();

        for (Integer i = 0; i < recordCount; i++) {
            contacts.add(new Contact(
                FirstName = 'Test ' + i,
                LastName = commonLastName
            ));
        }

        return contacts;
    }
}
