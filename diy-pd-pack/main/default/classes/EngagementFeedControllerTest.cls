@IsTest
public class EngagementFeedControllerTest {

    /* =========================================================
       Test Data Setup
    ========================================================= */

    @TestSetup
    static void setupData() {

        // Create Account
        Account acc = new Account(
            Name = 'Test Account'
        );
        insert acc;

        // Create Contact
        Contact con = new Contact(
            FirstName = 'Test',
            LastName = 'User',
            AccountId = acc.Id,
            Email = 'test@test.com'
        );
        insert con;
    }


    /* =========================================================
       Main Test Method
    ========================================================= */

    @IsTest
    static void testGetEngagementFeed_Success() {

        // Register HTTP Mock
        Test.setMock(HttpCalloutMock.class,
            new DataCloudCalloutMock()
        );

        // Get Account
        Account acc = [
            SELECT Id FROM Account LIMIT 1
        ];


        Test.startTest();

        // Call Apex
        List<EngagementFeedController.FeedItem> results =
            EngagementFeedController.getEngagementFeed(acc.Id);

        Test.stopTest();


        /* =========================
           Assertions
        ========================= */

        System.assertNotEquals(
            null,
            results,
            'Results should not be null'
        );

        System.assertEquals(
            2,
            results.size(),
            'Should return 2 feed items'
        );

        // First record
        EngagementFeedController.FeedItem item1 = results[0];

        System.assertEquals(
            'Added to Segment',
            item1.title
        );

        System.assertEquals(
            'Abandoned Shopping Cart',
            item1.description
        );

        System.assertEquals(
            'utility:groups',
            item1.icon
        );

        System.assertEquals(
            '#ba0517',
            item1.color
        );

        System.assert(
            item1.eventTime.contains('Jan'),
            'Date should be formatted'
        );
    }


    /* =========================================================
       No Contact Scenario
    ========================================================= */

    @IsTest
    static void testGetEngagementFeed_NoContact() {

        Account acc = new Account(Name='No Contact Acc');
        insert acc;

        Test.setMock(HttpCalloutMock.class,
            new DataCloudCalloutMock()
        );

        Test.startTest();

        List<EngagementFeedController.FeedItem> results =
            EngagementFeedController.getEngagementFeed(acc.Id);

        Test.stopTest();


        System.assertEquals(
            0,
            results.size(),
            'Should return empty when no contact exists'
        );
    }


    /* =========================================================
       HTTP Mock Class
    ========================================================= */

    private class DataCloudCalloutMock
        implements HttpCalloutMock {

        public HttpResponse respond(HttpRequest req) {

            // Validate request (optional)
            System.assertEquals(
                'POST',
                req.getMethod()
            );

            System.assert(
                req.getBody().contains('SELECT'),
                'SQL must be present'
            );


            HttpResponse res = new HttpResponse();

            res.setStatusCode(200);
            res.setHeader('Content-Type', 'application/json');

            // Fake Data Cloud Response
            res.setBody(
            '{' +
            '  "data": [' +
            '    ["001","CIN1","Added to Segment","Abandoned Shopping Cart","2026-01-26 05:45:11.000 UTC"],' +
            '    ["001","CIN1","SMS Campaign","Holiday SMS","2026-01-10 10:34:13.000 UTC"]' +
            '  ]' +
            '}'
            );

            return res;
        }
    }

}