@IsTest(seeAllData=false)
private class GetCustomersFromSegment_Test {

    /**
     * Simple reusable HTTP mock to simulate callout responses.
     * Asserts HTTP method and endpoint path to ensure the request is built correctly.
     */
    private class SimpleHttpMock implements HttpCalloutMock {
        private Integer code;
        private String body;

        SimpleHttpMock(Integer code, String body) {
            this.code = code;
            this.body = body;
        }

        public HTTPResponse respond(HTTPRequest req) {
            // Verify request basics
            System.assertEquals('GET', req.getMethod(), 'HTTP method must be GET');
            System.assert(
                req.getEndpoint().endsWith('/services/data/v62.0/ssot/segments/Power_Buyer_Program_Members/members'),
                'Unexpected endpoint: ' + req.getEndpoint()
            );

            // Build fake response
            HttpResponse res = new HttpResponse();
            res.setStatusCode(code);
            // Optional: status line not strictly required; keeping body + code is enough
            res.setBody(body);
            return res;
        }
    }

    // -------- Test data helpers --------
    private static Account makeAccount() {
        Account a = new Account(Name = 'Acme Inc');
        insert a;
        return a;
    }

    private static Contact makeContact(Id accountId, String unifiedId) {
        Contact c = new Contact(
            LastName = 'Tester',
            AccountId = accountId,
            Customer_Unified_Individual_Id__c = unifiedId
        );
        insert c;
        return c;
    }

    // -------- Tests --------

    @IsTest
    static void test_getSessionIdFromVFPage_returnsDummyInTests() {
        Test.startTest();
        String sid = GetCustomersFromSegment.getSessionIdFromVFPage();
        Test.stopTest();
        System.assertEquals('MY_SESSION_ID', sid, 'Should return test session id in test context');
    }

    @IsTest
    static void test_getContactSegmentStatus_EligibleMatch() {
        Account a = makeAccount();
        Contact c = makeContact(a.Id, 'IND123');

        String body = '{"data":[{"id":"IND123"}]}'; // ID matches the contact's unified id
        Test.setMock(HttpCalloutMock.class, new SimpleHttpMock(200, body));

        Test.startTest();
        String result = GetCustomersFromSegment.getContactSegmentStatus(a.Id);
        Test.stopTest();

        System.assertEquals(
            'Eligible for Power Buyer Upgrade Loyalty Program',
            result,
            'Should be eligible when a matching id is found'
        );
    }

    @IsTest
    static void test_getContactSegmentStatus_NotEligible_Mismatch() {
        Account a = makeAccount();
        Contact c = makeContact(a.Id, 'IND123');

        String body = '{"data":[{"id":"OTHER"}]}'; // Non-matching id
        Test.setMock(HttpCalloutMock.class, new SimpleHttpMock(200, body));

        Test.startTest();
        String result = GetCustomersFromSegment.getContactSegmentStatus(a.Id);
        Test.stopTest();

        System.assertEquals(
            'Not Eligible for Power Buyer Upgrade Loyalty Program',
            result,
            'Should not be eligible when id does not match'
        );
    }

    @IsTest
    static void test_getContactSegmentStatus_NoDataKey() {
        Account a = makeAccount();
        Contact c = makeContact(a.Id, 'IND123');

        String body = '{}'; // Missing "data" key
        Test.setMock(HttpCalloutMock.class, new SimpleHttpMock(200, body));

        Test.startTest();
        String result = GetCustomersFromSegment.getContactSegmentStatus(a.Id);
        Test.stopTest();

        System.assertEquals(
            'Not Eligible for upgrade',
            result,
            'Should return fallback message when data key missing'
        );
    }

    @IsTest
    static void test_getContactSegmentStatus_Non200Response() {
        Account a = makeAccount();
        Contact c = makeContact(a.Id, 'IND123');

        String body = '{"error":"Internal Server Error"}';
        Test.setMock(HttpCalloutMock.class, new SimpleHttpMock(500, body));

        Test.startTest();
        String result = GetCustomersFromSegment.getContactSegmentStatus(a.Id);
        Test.stopTest();

        System.assertEquals(
            'Not Eligible for Power Buyer Upgrade Loyalty Program',
            result,
            'Non-200 should result in default not-eligible message'
        );
    }

    @IsTest
    static void test_getContactSegmentStatus_InvalidJson_CaughtGracefully() {
        Account a = makeAccount();
        Contact c = makeContact(a.Id, 'IND123');

        // Invalid JSON to trigger exception in JSON.deserializeUntyped
        String body = 'not-json';
        Test.setMock(HttpCalloutMock.class, new SimpleHttpMock(200, body));

        Test.startTest();
        String result = GetCustomersFromSegment.getContactSegmentStatus(a.Id);
        Test.stopTest();

        System.assertEquals(
            'Not Eligible for Power Buyer Upgrade Loyalty Program',
            result,
            'Invalid JSON should be caught and return default message'
        );
    }

    @IsTest
    static void test_getContactSegmentStatus_NoContactFound() {
        Account a = makeAccount();
        // No contact created for this account

        Test.startTest();
        String result = GetCustomersFromSegment.getContactSegmentStatus(a.Id);
        Test.stopTest();

        System.assertEquals(
            'Not Eligible for Power Buyer Upgrade Loyalty Program',
            result,
            'When no contact exists, should return the default message'
        );
    }
}