@IsTest
public class ItemsOnSaleTest {

    @IsTest
    static void testGetProducts_WithMockData() {

        // =====================================================
        // 1) Mock PromotionProduct (using JSON to bypass read-only)
        // =====================================================
        List<SObject> promoMocks = new List<SObject>();

        SObject promo =
            (SObject) JSON.deserialize(
                '{"attributes":{"type":"ssot__PromotionProduct__dlm"}, "ssot__ProductId__c":"P001"}',
                SObject.class
            );

        promoMocks.add(promo);
        ItemsOnSale.mockPromotionProducts = promoMocks;

        // =====================================================
        // 2) Mock Product
        // =====================================================
        List<SObject> productMocks = new List<SObject>();

        SObject prod =
            (SObject) JSON.deserialize(
                '{"attributes":{"type":"ssot__Product__dlm"},' +
                '"ssot__Name__c":"Test Product",' +
                '"ssot__Description__c":"Test Description",' +
                '"Display_URL__c":"https://test.com/image.jpg"}',
                SObject.class
            );

        productMocks.add(prod);
        ItemsOnSale.mockProducts = productMocks;

        // =====================================================
        // 3) Execute
        // =====================================================
        List<ItemsOnSale.Request> reqList = new List<ItemsOnSale.Request>();
        reqList.add(new ItemsOnSale.Request());

        Test.startTest();
        List<PromptOutputADT> response = ItemsOnSale.getProducts(reqList);
        Test.stopTest();

        // =====================================================
        // 4) Assertions
        // =====================================================
        System.assertEquals(1, response.size());
        System.assertEquals(
            'Here are the products currently on sale.',
            response[0].message
        );
        System.assertNotEquals('[]', response[0].productsJson);
    }


    @IsTest
    static void testGetProducts_NoData() {

        ItemsOnSale.mockPromotionProducts = new List<SObject>();
        ItemsOnSale.mockProducts = new List<SObject>();

        List<ItemsOnSale.Request> reqList = new List<ItemsOnSale.Request>();
        reqList.add(new ItemsOnSale.Request());

        Test.startTest();
        List<PromptOutputADT> response = ItemsOnSale.getProducts(reqList);
        Test.stopTest();

        System.assertEquals(
            'There are no products currently on sale.',
            response[0].message
        );
        System.assertEquals('[]', response[0].productsJson);
    }
}