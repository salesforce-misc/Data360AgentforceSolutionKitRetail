global class ProductCarouselController {

    // ===============================
    // DTO
    // ===============================
    global class ProductDTO {
        @AuraEnabled public Id productId;
        @AuraEnabled public String name;
        @AuraEnabled public String imageUrl;
        @AuraEnabled public Decimal price;
        @AuraEnabled public String url;
        @AuraEnabled public String imageRedirectUrl;
        @AuraEnabled public Integer reviews; // ✅ NEW
    }

    // ===============================
    // ENTRY POINT
    // ===============================
    @AuraEnabled(cacheable=true)
    public static List<ProductDTO> getProducts(String type) {

        // RIGHT CAROUSEL (DISCOUNT)
        if (type == 'discount') {
            return getDiscountedProductsFromPromotions();
        }

        // LEFT CAROUSEL        
        Id accountId = getLoggedInAccountId();
        system.debug('## accountId = '+accountId);
        if (accountId != null) {
            return getRecentPurchasedProducts(accountId);
        }

        return getRandomProducts(5); // Guest → Trending
    }

    // ===============================
    // RECENT PURCHASED (LOGGED IN)
    // ===============================
    @TestVisible
    private static List<ProductDTO> getRecentPurchasedProducts(Id accountId) {

        List<ProductDTO> results = new List<ProductDTO>();
        //Set<Id> addedProductIds = new Set<Id>();
        Set<String> addedProductIds = new Set<String>();
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
            SELECT ssot__Id__c,ssot__BillToAccountId__c,ssot__BillToContactId__c,ssot__SoldToCustomerId__c FROM ssot__SalesOrder__dlm
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
            SELECT ssot__Id__c,ssot__ProductId__c,ssot__SalesOrderId__c,ssot__TotalLineAmount__c,ssot__UnitPriceAmount__c FROM ssot__SalesOrderProduct__dlm
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
            SELECT ssot__Id__c, ssot__Name__c, Display_URL__c
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
                System.debug('## addedProductIds = '+addedProductIds);
                //System.debug('## orderProduct.ssot__SalesOrderId__c = '+orderProduct.ssot__SalesOrderId__c);
                //System.debug('## salesOrder.ssot__Id__c = '+salesOrder.ssot__Id__c);
                //System.debug('## orderProduct.ssot__ProductId__c = '+orderProduct.ssot__ProductId__c);
                //if (!addedProductIds.contains(orderProduct.ssot__ProductId__c) && orderProduct.ssot__SalesOrderId__c == salesOrder.ssot__Id__c && orderProduct.ssot__ProductId__c != null) {
                if (!addedProductIds.contains(String.valueOf(orderProduct.ssot__ProductId__c)) && safeIdEquals(orderProduct.ssot__SalesOrderId__c, salesOrder.ssot__Id__c) && orderProduct.ssot__ProductId__c != null) {
                    ssot__Product__dlm product = productsMap.get(orderProduct.ssot__ProductId__c);
                    System.debug('## For Loop product = '+product);
                    if (product != null) {   
                        addedProductIds.add(product.ssot__Id__c);                    
                        ProductDTO dto = new ProductDTO();
                        dto.productId = product.ssot__Id__c;
                        dto.name = product.ssot__Name__c;
                        dto.imageUrl = product.Display_URL__c;
                        dto.price = orderProduct.ssot__TotalLineAmount__c;
                        dto.imageRedirectUrl = product.Display_URL__c;
                        //dto.url = '/DIYStorefront/product/' + product.ssot__Id__c;
                        dto.url = '/DIYStorefront/product/' + String.valueOf(product.ssot__Id__c);
                        dto.reviews = getHardcodedReviewCount(product.ssot__Id__c);
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

    // ===============================
    // TRENDING (RANDOM PRODUCTS)
    // ===============================
    private static List<ProductDTO> getRandomProducts(Integer limitSize) {

        /*List<Product2> products = [
            SELECT Id, Name, URL__c
            FROM Product2
            WHERE IsActive = true OR IsActive = false
            LIMIT 50
        ];*/

        List<ProductDTO> results = new List<ProductDTO>();

        List<ssot__Product__dlm> products = [
            SELECT ssot__Id__c, ssot__Name__c, Display_URL__c,ssot__IsActive__c,ssot__ProductSKU__c
            FROM ssot__Product__dlm 
            WHERE ssot__IsActive__c = 'true' and ssot__ProductSKU__c like '%SKU%'
            LIMIT 50
        ];

        if(products.isEmpty()){
            return results;
        }

        System.debug('## products = ' + products);

        Map<Decimal, ssot__Product__dlm> randomMap = new Map<Decimal, ssot__Product__dlm>();
        for (ssot__Product__dlm p : products) {
            randomMap.put(Math.random(), p);
        }

        List<Decimal> keys = new List<Decimal>(randomMap.keySet());
        keys.sort();

        
        Integer size = Math.min(limitSize, keys.size());

        for (Integer i = 0; i < size; i++) {
            ssot__Product__dlm p = randomMap.get(keys[i]);

            ProductDTO dto = new ProductDTO();
            dto.productId = p.ssot__Id__c;
            dto.name = p.ssot__Name__c;
            dto.imageUrl = p.Display_URL__c;
            dto.price = null;
            dto.imageRedirectUrl = p.Display_URL__c;            
            dto.url = '/DIYStorefront/product/' + String.valueOf(p.ssot__Id__c);
            dto.reviews = getHardcodedReviewCount(p.ssot__Id__c);
            results.add(dto);
        }

        System.debug('## results = ' + results);
        return results;
    }

    // ===============================
    // DISCOUNTED (PROMOTION PRODUCTS)
    // ===============================
    @TestVisible
    private static List<ProductDTO> getDiscountedProductsFromPromotions() {
        List<ProductDTO> results = new List<ProductDTO>();
        Set<Id> addedProductIds = new Set<Id>();
        List<ssot__PromotionOffer__dlm> promotionList = [SELECT ssot__Id__c,Discount__c,ssot__PromotionId__c FROM ssot__PromotionOffer__dlm Limit 5];
        
        if(promotionList.isEmpty()){
            return results;
        }

        Map<Id, ssot__PromotionOffer__dlm> promotionMap = new Map<Id, ssot__PromotionOffer__dlm>();
        Set<Id> promotionIds = new Set<Id>();
        for (ssot__PromotionOffer__dlm promotion : promotionList) {
            promotionIds.add(promotion.ssot__Id__c);
            promotionMap.put(promotion.ssot__Id__c, promotion);
        }

        List<ssot__PromotionProduct__dlm> promotionProductList = [SELECT ssot__Id__c,ssot__ProductId__c,ssot__PromotionId__c FROM ssot__PromotionProduct__dlm WHERE ssot__ProductId__c != NULL and  ssot__PromotionId__c IN :promotionIds];
        
        if(promotionProductList.isEmpty()){
            return results;
        }

        Set<Id> productIds = new Set<Id>();
        for (ssot__PromotionProduct__dlm promotionProduct : promotionProductList) {
            productIds.add(promotionProduct.ssot__ProductId__c);
        }

        List<ssot__Product__dlm> productlist = [
            SELECT ssot__Id__c, ssot__Name__c, Display_URL__c
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

        for (ssot__PromotionProduct__dlm promotionProduct : promotionProductList) {
            System.debug('## For Loop promotionProduct = '+promotionProduct);
            ssot__Product__dlm product = productsMap.get(promotionProduct.ssot__ProductId__c);
            System.debug('## For Loop product = '+product);
            ssot__PromotionOffer__dlm promotion = promotionMap.get(promotionProduct.ssot__PromotionId__c);
            System.debug('## For Loop promotion = '+promotion);
            if (!addedProductIds.contains(product.ssot__Id__c) && product != NULL && promotion != NULL) {  
                addedProductIds.add(product.ssot__Id__c);              
                ProductDTO dto = new ProductDTO();
                dto.productId = product.ssot__Id__c;
                dto.name = product.ssot__Name__c;
                dto.imageUrl = product.Display_URL__c;
                dto.price = promotion.Discount__c;
                dto.imageRedirectUrl = product.Display_URL__c;
                //dto.url = '/DIYStorefront/product/' + product.ssot__Id__c;
                dto.url = '/DIYStorefront/product/' + String.valueOf(product.ssot__Id__c);
                dto.reviews = getHardcodedReviewCount(product.ssot__Id__c);
                results.add(dto);
                productCount++;
            }
            if (productCount >= 5) break;            
        }

        System.debug('## results = ' + results);
        return results;
    }

    // ===============================
    // HARD-CODED REVIEW LOGIC (STABLE)
    // ===============================
    private static Integer getHardcodedReviewCount(Id productId) {
        Integer hash = Math.abs(String.valueOf(productId).hashCode());
        return Math.mod(hash, 1200) + 10; // 10 → 1209 reviews
    }

    // ===============================
    // USER CONTEXT (GUEST SAFE)
    // ===============================
    private static Id getLoggedInContactId() {
        try {
            return [
                SELECT ContactId
                FROM User
                WHERE Id = :UserInfo.getUserId()
            ].ContactId;
        } catch (Exception e) {
            return null;
        }
    }

    // ===============================
    // USER CONTEXT (GUEST SAFE)
    // ===============================
    private static Id getLoggedInAccountId() {
        try {
            return [
                SELECT AccountId
                FROM User
                WHERE Id = :UserInfo.getUserId() and AccountId != NULL
            ].AccountId;
        } catch (Exception e) {
            return null;
        }
    }
    
    // ===============================
    // SAFE ID COMPARISON (TEST STABLE)
    // ===============================
    @TestVisible
    private static Boolean safeIdEquals(Id a, Id b) {
        if (a == null || b == null) return false;
        return String.valueOf(a) == String.valueOf(b);
    }
}