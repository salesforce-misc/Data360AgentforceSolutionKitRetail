@IsTest
public class ValidateContactContextTest {

    @IsTest
    static void testValidContactId() {

        // Create a real Contact (needed to get 003 prefix)
        Contact c = new Contact(LastName = 'Test');
        insert c;

        // Prepare request
        ValidateContactContext.Request req = new ValidateContactContext.Request();
        req.contactId = c.Id;

        List<ValidateContactContext.Request> reqList =
            new List<ValidateContactContext.Request>{ req };

        // Execute
        Test.startTest();
        List<ValidateContactContext.Response> resList =
            ValidateContactContext.validate(reqList);
        Test.stopTest();

        // Assertions
        System.assertEquals(1, resList.size());
        System.assertEquals(false, resList[0].isGuest);
        System.assertEquals(c.Id, resList[0].contactId);
    }


    @IsTest
    static void testInvalidContactId() {

        // Create a fake non-contact Id (like Data Cloud / other object)
        Id fakeId = '001000000000001AAA'; // Account type (001)

        ValidateContactContext.Request req = new ValidateContactContext.Request();
        req.contactId = fakeId;

        List<ValidateContactContext.Request> reqList =
            new List<ValidateContactContext.Request>{ req };

        // Execute
        Test.startTest();
        List<ValidateContactContext.Response> resList =
            ValidateContactContext.validate(reqList);
        Test.stopTest();

        // Assertions
        System.assertEquals(1, resList.size());
        System.assertEquals(true, resList[0].isGuest);
        System.assertEquals(null, resList[0].contactId);
    }


    @IsTest
    static void testNullContactId() {

        ValidateContactContext.Request req = new ValidateContactContext.Request();
        req.contactId = null;

        List<ValidateContactContext.Request> reqList =
            new List<ValidateContactContext.Request>{ req };

        // Execute
        Test.startTest();
        List<ValidateContactContext.Response> resList =
            ValidateContactContext.validate(reqList);
        Test.stopTest();

        // Assertions
        System.assertEquals(1, resList.size());
        System.assertEquals(true, resList[0].isGuest);
        System.assertEquals(null, resList[0].contactId);
    }
}