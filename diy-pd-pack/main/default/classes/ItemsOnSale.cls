public with sharing class ItemsOnSale {

    public class Request {
        @InvocableVariable(required=false)
        public String input;
    }

    // DTO for Adaptive Response carousel
    public class SalesPromoDTO {
        public String title;
        public String description;
        public String imageUrl;
    }

    // Test Mock Support
    @TestVisible static List<SObject> mockPromotionProducts;
    @TestVisible static List<SObject> mockProducts;

    @InvocableMethod(
        label='Get Promotion Products For Sale'
        description='Returns sale products for Adaptive Response carousel'
    )
    public static List<PromptOutputADT> getProducts(List<Request> requests) {

        Integer limitSize = 5;

        List<PromptOutputADT> results = new List<PromptOutputADT>();
        PromptOutputADT res = new PromptOutputADT();
        res.message = '';
        res.productsJson = '[]';

        // 1) Get Promotion Product IDs
        Set<String> promoProductIds = new Set<String>();

        List<SObject> promoRecords;

        if (Test.isRunningTest() && mockPromotionProducts != null) {
            promoRecords = mockPromotionProducts;
        } else {
            promoRecords = [
                SELECT ssot__ProductId__c
                FROM ssot__PromotionProduct__dlm
                WHERE ssot__ProductId__c != null
                LIMIT 5
            ];
        }

        for (SObject pp : promoRecords) {
            promoProductIds.add((String)pp.get('ssot__ProductId__c'));
        }

        if (promoProductIds.isEmpty()) {
            res.message = 'There are no products currently on sale.';
            results.add(res);
            return results;
        }

        // 2) Query Products
        List<SObject> products;

        if (Test.isRunningTest() && mockProducts != null) {
            products = mockProducts;
        } else {
            products = Database.query(
                'SELECT ssot__Name__c, ssot__Description__c, Display_URL__c ' +
                'FROM ssot__Product__dlm ' +
                'WHERE ssot__Id__c IN :promoProductIds ' +
                'LIMIT :limitSize'
            );
        }

        if (products.isEmpty()) {
            res.message = 'There are no products currently on sale.';
            results.add(res);
            return results;
        }

        // 3) Build DTO List
        List<SalesPromoDTO> dtoList = new List<SalesPromoDTO>();

        for (SObject p : products) {
            SalesPromoDTO dto = new SalesPromoDTO();
            dto.title = (String)p.get('ssot__Name__c');
            dto.description = (String)p.get('ssot__Description__c');
            dto.imageUrl = (String)p.get('Display_URL__c');
            dtoList.add(dto);
        }

        // 4) Message + JSON
		res.message = 'Here are the products currently on sale.';
        res.productsJson = JSON.serialize(dtoList);

        results.add(res);
        return results;
    }
}