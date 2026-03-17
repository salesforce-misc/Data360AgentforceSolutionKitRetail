@IsTest
private class HVACWarrantyServiceTest {

    // =====================================================
    // Helper Methods
    // =====================================================

    private static Contact createContact(Boolean withAccount) {
        Account acc;
        if (withAccount) {
            acc = new Account(Name = 'Test Account');
            insert acc;
        }

        Contact con = new Contact(
            LastName = 'Test Contact',
            AccountId = withAccount ? acc.Id : null
        );
        insert con;
        return con;
    }

    private static ssot__SalesOrder__dlm createMockOrder(String idVal, DateTime dtVal) {
        String jsonStr = JSON.serialize(new Map<String, Object>{
            'ssot__Id__c' => idVal,
            'ssot__OrderStartDate__c' => dtVal
        });

        return (ssot__SalesOrder__dlm)
            JSON.deserialize(jsonStr, ssot__SalesOrder__dlm.class);
    }

    private static void resetMocks() {
        HVACWarrantyService.mockProductIds = null;
        HVACWarrantyService.mockOrders = null;
        HVACWarrantyService.mockOrdersWithHvac = null;
    }

    // =====================================================
    // 1. Full Flow – Latest Date Calculated
    // =====================================================
    @IsTest
    static void testFullFlow_WithMockData() {

        Contact con = createContact(true);

        HVACWarrantyService.mockProductIds = new Set<String>{'PROD1'};

        ssot__SalesOrder__dlm order1 =
            createMockOrder('ORD1', System.now().addYears(-4));
        ssot__SalesOrder__dlm order2 =
            createMockOrder('ORD2', System.now().addYears(-5));

        HVACWarrantyService.mockOrders = new List<ssot__SalesOrder__dlm>{
            order1, order2
        };

        HVACWarrantyService.mockOrdersWithHvac = new Set<String>{'ORD1'};

        HVACWarrantyService.HVACRequest req = new HVACWarrantyService.HVACRequest();
        req.contactId = con.Id;

        Test.startTest();
        List<HVACWarrantyService.HVACMessageResult> res =
            HVACWarrantyService.getHVACMessage(
                new List<HVACWarrantyService.HVACRequest>{req}
            );
        Test.stopTest();

        System.assertEquals(1, res.size());
        System.assert(!res[0].message.contains('TBD'));

        resetMocks();
    }

    // =====================================================
    // 2. Null Request List
    // =====================================================
    @IsTest
    static void testNullRequestList() {
        Test.startTest();
        List<HVACWarrantyService.HVACMessageResult> res =
            HVACWarrantyService.getHVACMessage(null);
        Test.stopTest();

        System.assertEquals(0, res.size());
    }

    // =====================================================
    // 3. Null ContactId
    // =====================================================
    @IsTest
    static void testNullContactId() {

        HVACWarrantyService.HVACRequest req = new HVACWarrantyService.HVACRequest();
        req.contactId = null;

        Test.startTest();
        List<HVACWarrantyService.HVACMessageResult> res =
            HVACWarrantyService.getHVACMessage(
                new List<HVACWarrantyService.HVACRequest>{req}
            );
        Test.stopTest();

        System.assertEquals(1, res.size());
        System.assert(res[0].message.contains('TBD'));
    }

    // =====================================================
    // 4. Invalid Id
    // =====================================================
    @IsTest
    static void testInvalidId() {

        HVACWarrantyService.HVACRequest req = new HVACWarrantyService.HVACRequest();
        req.contactId = UserInfo.getUserId();

        Test.startTest();
        List<HVACWarrantyService.HVACMessageResult> res =
            HVACWarrantyService.getHVACMessage(
                new List<HVACWarrantyService.HVACRequest>{req}
            );
        Test.stopTest();

        System.assertEquals(1, res.size());
    }

    // =====================================================
    // 5. AccountId Path
    // =====================================================
    @IsTest
    static void testAccountIdInput() {

        Contact con = createContact(true);

        HVACWarrantyService.mockProductIds = new Set<String>{'PROD1'};
        HVACWarrantyService.mockOrders = new List<ssot__SalesOrder__dlm>();
        HVACWarrantyService.mockOrdersWithHvac = new Set<String>();

        HVACWarrantyService.HVACRequest req = new HVACWarrantyService.HVACRequest();
        req.contactId = con.AccountId;

        Test.startTest();
        List<HVACWarrantyService.HVACMessageResult> res =
            HVACWarrantyService.getHVACMessage(
                new List<HVACWarrantyService.HVACRequest>{req}
            );
        Test.stopTest();

        System.assertEquals(1, res.size());

        resetMocks();
    }

    // =====================================================
    // 6. HVAC Products Empty
    // =====================================================
    @IsTest
    static void testNoHVACProducts() {

        Contact con = createContact(false);

        HVACWarrantyService.mockProductIds = new Set<String>();

        HVACWarrantyService.HVACRequest req = new HVACWarrantyService.HVACRequest();
        req.contactId = con.Id;

        Test.startTest();
        List<HVACWarrantyService.HVACMessageResult> res =
            HVACWarrantyService.getHVACMessage(
                new List<HVACWarrantyService.HVACRequest>{req}
            );
        Test.stopTest();

        System.assertEquals(1, res.size());

        resetMocks();
    }

    // =====================================================
    // 7. Orders Empty
    // =====================================================
    @IsTest
    static void testNoOrders() {

        Contact con = createContact(false);

        HVACWarrantyService.mockProductIds = new Set<String>{'PROD1'};
        HVACWarrantyService.mockOrders = new List<ssot__SalesOrder__dlm>();

        HVACWarrantyService.HVACRequest req = new HVACWarrantyService.HVACRequest();
        req.contactId = con.Id;

        Test.startTest();
        List<HVACWarrantyService.HVACMessageResult> res =
            HVACWarrantyService.getHVACMessage(
                new List<HVACWarrantyService.HVACRequest>{req}
            );
        Test.stopTest();

        System.assertEquals(1, res.size());

        resetMocks();
    }

    // =====================================================
    // 8. Orders Without HVAC Items
    // =====================================================
    @IsTest
    static void testOrdersWithoutHVACItems() {

        Contact con = createContact(false);

        HVACWarrantyService.mockProductIds = new Set<String>{'PROD1'};

        ssot__SalesOrder__dlm order1 =
            createMockOrder('ORD100', System.now().addYears(-4));

        HVACWarrantyService.mockOrders =
            new List<ssot__SalesOrder__dlm>{order1};

        HVACWarrantyService.mockOrdersWithHvac = new Set<String>();

        HVACWarrantyService.HVACRequest req = new HVACWarrantyService.HVACRequest();
        req.contactId = con.Id;

        Test.startTest();
        List<HVACWarrantyService.HVACMessageResult> res =
            HVACWarrantyService.getHVACMessage(
                new List<HVACWarrantyService.HVACRequest>{req}
            );
        Test.stopTest();

        System.assertEquals(1, res.size());

        resetMocks();
    }

    // =====================================================
    // 9. OrderIds Empty
    // =====================================================
    @IsTest
    static void testOrderIdsEmpty() {

        Contact con = createContact(false);

        HVACWarrantyService.mockProductIds = new Set<String>{'PROD1'};

        ssot__SalesOrder__dlm order1 =
            createMockOrder(null, System.now().addYears(-4));

        HVACWarrantyService.mockOrders =
            new List<ssot__SalesOrder__dlm>{order1};

        HVACWarrantyService.HVACRequest req = new HVACWarrantyService.HVACRequest();
        req.contactId = con.Id;

        Test.startTest();
        List<HVACWarrantyService.HVACMessageResult> res =
            HVACWarrantyService.getHVACMessage(
                new List<HVACWarrantyService.HVACRequest>{req}
            );
        Test.stopTest();

        System.assertEquals(1, res.size());

        resetMocks();
    }

}