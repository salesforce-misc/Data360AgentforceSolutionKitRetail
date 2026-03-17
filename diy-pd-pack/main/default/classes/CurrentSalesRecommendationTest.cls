@IsTest
private class CurrentSalesRecommendationTest {

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

    private static String fakeId(String prefix) {
        return prefix + '000000000000AAA';
    }

    private static ssot__SalesOrder__dlm mockOrder(String idVal, Id contactId) {
        return (ssot__SalesOrder__dlm) JSON.deserialize(
            JSON.serialize(new Map<String,Object>{
                'ssot__Id__c' => idVal,
                'ssot__BillToContactId__c' => contactId,
                'ssot__OrderStartDate__c' => System.now()
            }),
            ssot__SalesOrder__dlm.class
        );
    }

    private static ssot__SalesOrderProduct__dlm mockOrderProduct(String soId, String prodId) {
        return (ssot__SalesOrderProduct__dlm) JSON.deserialize(
            JSON.serialize(new Map<String,Object>{
                'ssot__SalesOrderId__c' => soId,
                'ssot__ProductId__c' => prodId
            }),
            ssot__SalesOrderProduct__dlm.class
        );
    }

    private static ssot__Product__dlm mockProduct(String idVal, String family) {
        return (ssot__Product__dlm) JSON.deserialize(
            JSON.serialize(new Map<String,Object>{
                'ssot__Id__c' => idVal,
                'ssot__Name__c' => 'Product ' + idVal,
                'ssot__Description__c' => 'Desc',
                'Display_URL__c' => 'url',
                'ssot__ProductFamily__c' => family,
                'ssot__ProductSKU__c' => 'SKU-' + idVal
            }),
            ssot__Product__dlm.class
        );
    }

    private static void resetMocks() {
        CurrentSalesRecommendation.mockRecentOrders = null;
        CurrentSalesRecommendation.mockOrderProducts = null;
        CurrentSalesRecommendation.mockPurchasedProducts = null;
        CurrentSalesRecommendation.mockCandidateProducts = null;
    }

    // =====================================================
    // 1. Full Flow Coverage
    // =====================================================
    @IsTest
    static void testFullRecommendationFlow() {

        Contact con = createContact(false);

        String soId = fakeId('a01');
        String purchasedProd = fakeId('a02');
        String candidateProd = fakeId('a03');

        CurrentSalesRecommendation.mockRecentOrders =
            new List<ssot__SalesOrder__dlm>{
                mockOrder(soId, con.Id)
            };

        CurrentSalesRecommendation.mockOrderProducts =
            new List<ssot__SalesOrderProduct__dlm>{
                mockOrderProduct(soId, purchasedProd)
            };

        CurrentSalesRecommendation.mockPurchasedProducts =
            new List<ssot__Product__dlm>{
                mockProduct(purchasedProd, 'FamilyA')
            };

        CurrentSalesRecommendation.mockCandidateProducts =
            new List<ssot__Product__dlm>{
                mockProduct(candidateProd, 'FamilyA')
            };

        CurrentSalesRecommendation.RecommendationRequest req =
            new CurrentSalesRecommendation.RecommendationRequest();
        req.contactId = con.Id;

        Test.startTest();
        List<PromptOutputADT> res =
            CurrentSalesRecommendation.recommend(
                new List<CurrentSalesRecommendation.RecommendationRequest>{ req }
            );
        Test.stopTest();

        System.assertEquals(1, res.size());
        System.assert(res[0].productsJson.contains('Product'));
        System.assert(res[0].message.contains('inventory'));

        resetMocks();
    }

    // =====================================================
    // 2. No Orders Path
    // Covers: recentOrders.isEmpty()
    // =====================================================
    @IsTest
    static void testNoRecentOrders() {

        Contact con = createContact(false);

        CurrentSalesRecommendation.mockRecentOrders =
            new List<ssot__SalesOrder__dlm>();

        CurrentSalesRecommendation.RecommendationRequest req =
            new CurrentSalesRecommendation.RecommendationRequest();
        req.contactId = con.Id;

        List<PromptOutputADT> res =
            CurrentSalesRecommendation.recommend(
                new List<CurrentSalesRecommendation.RecommendationRequest>{ req }
            );

        System.assertEquals(1, res.size());

        resetMocks();
    }

    // =====================================================
    // 3. Orders exist but No Products
    // Covers: purchasedProductIds.isEmpty()
    // =====================================================
    @IsTest
    static void testOrdersButNoProducts() {

        Contact con = createContact(false);
        String soId = fakeId('a10');

        CurrentSalesRecommendation.mockRecentOrders =
            new List<ssot__SalesOrder__dlm>{
                mockOrder(soId, con.Id)
            };

        CurrentSalesRecommendation.mockOrderProducts =
            new List<ssot__SalesOrderProduct__dlm>();

        CurrentSalesRecommendation.RecommendationRequest req =
            new CurrentSalesRecommendation.RecommendationRequest();
        req.contactId = con.Id;

        List<PromptOutputADT> res =
            CurrentSalesRecommendation.recommend(
                new List<CurrentSalesRecommendation.RecommendationRequest>{ req }
            );

        System.assertEquals(1, res.size());

        resetMocks();
    }

    // =====================================================
    // 4. Multiple Families (Sorting + Phrase)
    // =====================================================
    @IsTest
    static void testMultipleFamiliesCoverage() {

        Contact con = createContact(false);
        String soId = fakeId('a20');

        CurrentSalesRecommendation.mockRecentOrders =
            new List<ssot__SalesOrder__dlm>{
                mockOrder(soId, con.Id)
            };

        CurrentSalesRecommendation.mockOrderProducts =
            new List<ssot__SalesOrderProduct__dlm>{
                mockOrderProduct(soId, fakeId('a21')),
                mockOrderProduct(soId, fakeId('a22'))
            };

        CurrentSalesRecommendation.mockPurchasedProducts =
            new List<ssot__Product__dlm>{
                mockProduct(fakeId('a21'), 'FamilyA'),
                mockProduct(fakeId('a22'), 'FamilyB')
            };

        CurrentSalesRecommendation.mockCandidateProducts =
            new List<ssot__Product__dlm>{
                mockProduct(fakeId('a23'), 'FamilyA'),
                mockProduct(fakeId('a24'), 'FamilyB')
            };

        CurrentSalesRecommendation.RecommendationRequest req =
            new CurrentSalesRecommendation.RecommendationRequest();
        req.contactId = con.Id;

        List<PromptOutputADT> res =
            CurrentSalesRecommendation.recommend(
                new List<CurrentSalesRecommendation.RecommendationRequest>{ req }
            );

        System.assertEquals(1, res.size());
        System.assert(res[0].message.contains('inventory'));

        resetMocks();
    }

    // =====================================================
    // 5. Basic Branches
    // =====================================================
    @IsTest
    static void testNullRequests() {
        List<PromptOutputADT> res =
            CurrentSalesRecommendation.recommend(null);
        System.assertEquals(0, res.size());
    }

    @IsTest
    static void testInvalidContact() {

        CurrentSalesRecommendation.RecommendationRequest req =
            new CurrentSalesRecommendation.RecommendationRequest();
        req.contactId = UserInfo.getUserId();

        List<PromptOutputADT> res =
            CurrentSalesRecommendation.recommend(
                new List<CurrentSalesRecommendation.RecommendationRequest>{ req }
            );

        System.assertEquals(1, res.size());
    }

    @IsTest
    static void testAccountIdInput() {

        Contact con = createContact(true);

        CurrentSalesRecommendation.RecommendationRequest req =
            new CurrentSalesRecommendation.RecommendationRequest();
        req.contactId = con.AccountId;

        List<PromptOutputADT> res =
            CurrentSalesRecommendation.recommend(
                new List<CurrentSalesRecommendation.RecommendationRequest>{ req }
            );

        System.assertEquals(1, res.size());
    }
}