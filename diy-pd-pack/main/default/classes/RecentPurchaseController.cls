global class RecentPurchaseController {
    // ===============================
    // DTO
    // ===============================
    global class ProductDTO {
        @AuraEnabled public String productName;
        @AuraEnabled public String description;
        @AuraEnabled public String family;
        @AuraEnabled public Decimal quantity;
        @AuraEnabled public Decimal unitPrice;
        @AuraEnabled public Datetime orderDate;
        @AuraEnabled public String imageUrl; 
    }

    @AuraEnabled(cacheable=true)
    public static List<ProductDTO> getRecentPurchasedProducts(Id accountId) {

        List<ProductDTO> results = new List<ProductDTO>();
        Set<Id> addedProductIds = new Set<Id>();
        List<ssot__Account__dlm> acc = [
            SELECT ssot__Id__c,ssot__AccountType__c,Contact_Id__c 
            FROM ssot__Account__dlm
            WHERE ssot__Id__c = :accountId
            LIMIT 1
        ];

        if(acc.isEmpty()){
            return results;
        }

        Id contactId;
        Boolean isPersonAccount = acc[0].ssot__AccountType__c != null && acc[0].ssot__AccountType__c == 'Person';
        Boolean hasContactId = acc[0].Contact_Id__c != null;

        if (!(isPersonAccount && hasContactId)) {
            return results;
        }

        contactId = acc[0].Contact_Id__c;

        List<ssot__SalesOrder__dlm> salesOrders = [
            SELECT ssot__Id__c,ssot__BillToAccountId__c,ssot__OrderStartDate__c,ssot__BillToContactId__c,ssot__SoldToCustomerId__c FROM ssot__SalesOrder__dlm
            WHERE ssot__SoldToCustomerId__c = :contactId and ssot__BillToContactId__c = :contactId and ssot__BillToAccountId__c = :accountId
            ORDER BY ssot__OrderStartDate__c DESC LIMIT 5
        ];

        if(salesOrders.isEmpty()){
            return results;
        }

        Set<Id> salesOrderIds = new Set<Id>();
        for (ssot__SalesOrder__dlm salesOrder : salesOrders) {
            salesOrderIds.add(salesOrder.ssot__Id__c);
        }

        List<ssot__SalesOrderProduct__dlm> salesOrderProducts = [
            SELECT ssot__Id__c,ssot__ProductId__c,ssot__SalesOrderId__c,ssot__OrderedQuantity__c,ssot__TotalLineAmount__c,ssot__UnitPriceAmount__c FROM ssot__SalesOrderProduct__dlm
            WHERE ssot__SalesOrderId__c IN :salesOrderIds
        ];

        if(salesOrderProducts.isEmpty()){
            return results;
        }

        Set<Id> productIds = new Set<Id>();
        for (ssot__SalesOrderProduct__dlm orderProduct : salesOrderProducts) {
            if (orderProduct.ssot__ProductId__c != null) {
                productIds.add(orderProduct.ssot__ProductId__c);
            }
        }

        List<ssot__Product__dlm> productlist = [
            SELECT ssot__Id__c, ssot__Name__c, Display_URL__c,ssot__Description__c,ssot__ProductFamily__c
            FROM ssot__Product__dlm 
            WHERE ssot__Id__c IN :productIds
        ];

        if(productlist.isEmpty()){
            return results;
        }

        Map<Id, ssot__Product__dlm> productsMap = new Map<Id, ssot__Product__dlm>();
        for (ssot__Product__dlm prod : productlist) {
            productsMap.put(prod.ssot__Id__c, prod);
        }


        Integer productCount = 0;

        for (ssot__SalesOrder__dlm salesOrder : salesOrders) {
            System.debug('## For Loop salesOrder = '+salesOrder);
            for (ssot__SalesOrderProduct__dlm orderProduct : salesOrderProducts) {
                System.debug('## For Loop orderProduct = '+orderProduct);
                if (!addedProductIds.contains(orderProduct.ssot__ProductId__c) && orderProduct.ssot__SalesOrderId__c == salesOrder.ssot__Id__c && orderProduct.ssot__ProductId__c != null) {
                    ssot__Product__dlm product = productsMap.get(orderProduct.ssot__ProductId__c);
                    System.debug('## For Loop product = '+product);
                    if (product != null) {   
                        addedProductIds.add(product.ssot__Id__c);                    
                        ProductDTO dto = new ProductDTO();
                        dto.productName = product.ssot__Name__c;
                        dto.description = product.ssot__Description__c;
                        dto.family = product.ssot__ProductFamily__c;
                        dto.quantity = orderProduct.ssot__OrderedQuantity__c;
                        dto.unitPrice = orderProduct.ssot__UnitPriceAmount__c;
                        dto.orderDate = salesOrder.ssot__OrderStartDate__c;
                        dto.imageUrl = product.Display_URL__c;
                        results.add(dto);
                        productCount++;
                    }
                }
                if (productCount >= 5) break;
            }
            if (productCount >= 5) break;
        }

        System.debug('## results = ' + results);
        return results;
    }
}