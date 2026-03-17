public class GenericProductService {

    /* ===== Response class for product recommendations ===== */
    public class Response {
        @InvocableVariable
        public List<String> messages = new List<String>();

         @InvocableVariable
        public List<ssot__Product__dlm> products = new List<ssot__Product__dlm>();
    }
     
	/* =========================================================
      LOGIC 1: CustomerPromotionEligibility (UNCHANGED)
     ========================================================= */
      public static Response customerPromotionEligibility(Id contactId) {
    
        Response result = new Response();
        if (contactId == null) return result;
    
        // Data Cloud typically stores IDs in ssot__*__c fields as Strings
        String contactIdStr = String.valueOf(contactId);
    
        // Keep the structure same, but use String-based ids for DLM data
        List<String> contactIds = new List<String>{ contactIdStr };
    
        Map<String, Set<String>> contactToOrderedProductIds = new Map<String, Set<String>>();
        contactToOrderedProductIds.put(contactIdStr, new Set<String>());
    
        
        // 1) Query Sales Orders to get order ids + BillToContactId
        Map<String, String> orderIdToBillToContactId = new Map<String, String>();
        Set<String> orderIds = new Set<String>();
          
        List<ssot__SalesOrder__dlm> orderList = [ SELECT ssot__Id__c, ssot__BillToContactId__c FROM ssot__SalesOrder__dlm
                                                  WHERE ssot__BillToContactId__c IN :contactIds];
    
        for (ssot__SalesOrder__dlm so : orderList) {
            if (so.ssot__Id__c != null) {
                orderIds.add(so.ssot__Id__c);
                orderIdToBillToContactId.put(so.ssot__Id__c, so.ssot__BillToContactId__c);
            }
        }
    
        // 2) Query SalesOrderProduct for those orders and collect ordered product ids
        if (!orderIds.isEmpty()) {
            List<ssot__SalesOrderProduct__dlm> orderProductList = [ SELECT ssot__SalesOrderId__c, ssot__ProductId__c
                    FROM ssot__SalesOrderProduct__dlm WHERE ssot__SalesOrderId__c IN :orderIds 
                   AND ssot__ProductId__c != NULL];
            for (ssot__SalesOrderProduct__dlm oi :orderProductList) {
                String billTo = orderIdToBillToContactId.get(oi.ssot__SalesOrderId__c);
                if (billTo != null && contactToOrderedProductIds.containsKey(billTo)) {
                    contactToOrderedProductIds.get(billTo).add(oi.ssot__ProductId__c);
                }
            }
        }
    
        Map<String, List<String>> productIdToPromoDescriptions = new Map<String, List<String>>();
        Set<String> promoProductIds = new Set<String>();
        List<ssot__PromotionProduct__dlm> promotionProductList = [SELECT ssot__ProductId__c, ssot__PromotionId__c
           			 FROM ssot__PromotionProduct__dlm WHERE ssot__ProductId__c != NULL];
    
        // PromotionProduct -> ssot__PromotionProduct__dlm (only ProductId + PromotionId available)
        for (ssot__PromotionProduct__dlm pp :promotionProductList ) {
            promoProductIds.add(pp.ssot__ProductId__c);
    
            if (!productIdToPromoDescriptions.containsKey(pp.ssot__ProductId__c)) {
                productIdToPromoDescriptions.put(pp.ssot__ProductId__c, new List<String>());
            }
    
            // No description available on PromotionProduct DLM in your model
            String rawDesc = 'Currently on sale';
            productIdToPromoDescriptions.get(pp.ssot__ProductId__c).add(rawDesc);
        }
    
        Map<String, ssot__Product__dlm> productById = new Map<String, ssot__Product__dlm>();
        if (!promoProductIds.isEmpty()) { 
           List<ssot__Product__dlm> productList = [ SELECT ssot__Id__c, ssot__Name__c, Display_URL__c, ssot__Description__c
                                                   FROM ssot__Product__dlm WHERE ssot__Id__c IN :promoProductIds];
            for (ssot__Product__dlm p : productList) {
                productById.put(p.ssot__Id__c, p);
            }
        }
    
        Set<String> addedProducts = new Set<String>();
        Set<String> orderedProducts = contactToOrderedProductIds.get(contactIdStr);
    
        for (String promoProdId : promoProductIds) {
    
            if (orderedProducts != null && orderedProducts.contains(promoProdId)) {
                continue;
            }
    
            ssot__Product__dlm prod = productById.get(promoProdId);
            String productName =
                (prod != null && !String.isBlank(prod.ssot__Name__c))
                ? prod.ssot__Name__c
                : String.valueOf(promoProdId);
    
            if (prod != null && !addedProducts.contains(prod.ssot__Id__c)) {
                result.products.add(prod);
                addedProducts.add(prod.ssot__Id__c);
            }
    
            List<String> descs = productIdToPromoDescriptions.get(promoProdId);
            if (descs != null) {
                for (String d : descs) {
                    result.messages.add(productName + ' has discount of: ' + d);
                }
            }
        }
    
        return result;
    } 
    /* Create RecentPurchasedOrder Details*/
     public static Set<String> getRecentProductIds(Id contactId) {
         
		 Set<String> pastProductSet = new Set<String>();
		  Set<String> orderIdSet = new Set<String>();
         List<ssot__SalesOrder__dlm> orders = [SELECT ssot__Id__c,ssot__BillToContactId__c,ssot__OrderStartDate__c FROM ssot__SalesOrder__dlm 
                                              WHERE ssot__BillToContactId__c = :contactId AND ssot__OrderStartDate__c >= LAST_N_DAYS:90];

		  system.debug('orders:'+orders);
        if (orders.isEmpty()) return new Set<String>();

        for(ssot__SalesOrder__dlm ord : orders){
            orderIdSet.add(ord.ssot__Id__c);
        }
         
		 
        List<ssot__SalesOrderProduct__dlm> orderProductList = [SELECT ssot__Id__c, ssot__SalesOrderId__c,ssot__ProductId__c  FROM ssot__SalesOrderProduct__dlm
            								WHERE ssot__SalesOrderId__c IN :orderIdSet];
        system.debug('orderProductList:'+orderProductList);
		   if(!orderProductList.isEmpty()){
            for(ssot__SalesOrderProduct__dlm oi : orderProductList){
            pastProductSet.add(oi.ssot__ProductId__c);  
           }
        }
        system.debug('pastProductSet:'+pastProductSet);
		
			return pastProductSet;
     
     }
    /* ===== Logic 1: Storage Product Recommendations ===== */
    public static Response returnStorageRecommendation(Id contactId){
        Response result = new Response();
        if(contactId == null) return result;
        
        Contact contactListId = [Select id,name,accountId from Contact where id =:contactId OR accountId =:contactId limit 1];
        Id conId = contactListId.id;
        system.debug('conId:'+conId);
        
          Set<String> pastFamilySet = new Set<String>();
		  List<ssot__Product__dlm> prodList = new List<ssot__Product__dlm>();
		  
       Set<String> pastProductIds = getRecentProductIds(conId);
        if (pastProductIds.isEmpty()) return result;
        

        List<ssot__Product__dlm> productList = [  SELECT ssot__Id__c, ssot__Name__c, ssot__Description__c, ssot__ProductFamily__c, Display_URL__c
                                               FROM ssot__Product__dlm ];
        system.debug('productList:'+productList);

		if(!productList.isEmpty()){
	      for(ssot__Product__dlm prod : productList){
			String familyName = prod.ssot__ProductFamily__c;
            if((pastProductIds != null && pastProductIds.contains(prod.ssot__Id__c)) && familyName != null){
                if(prod.ssot__ProductFamily__c == 'Power Tools'){
                       pastFamilySet.add(prod.ssot__ProductFamily__c);
                }
            }
			
			if(prod.ssot__ProductFamily__c == 'Storage'){
			  prodList.add(prod);
			}
          }
		}
        
        system.debug('pastFamilySet:'+pastFamilySet);

        if(!pastFamilySet.isEmpty()){
            result.messages.add(
                'I noticed you’ve picked up several ' + 
                String.join(new List<String>(pastFamilySet), ', ') + 
                ' recently.'
            );
        }else{
			result.messages.add(
                'You have not purchased any power tools recently ');
		}
		
        if(!prodList.isEmpty()){
               result.products.addAll(prodList);
        }
       system.debug('result:'+result);

        return result;
    }
    
      /* =========================================================
       LOGIC 2: ReturnBladeProductFeature
       ========================================================= */
    public static Response returnBladeRecomendation(Id contactId){
         Response result = new Response();
        if(contactId == null) return result;
        
        Contact contactListId = [Select id,name,accountId from Contact where id =:contactId OR accountId =:contactId limit 1];
        Id conId = contactListId.id;
        system.debug('conId:'+conId);
	
        List<ssot__Product__dlm> familyBladeProducts = new List<ssot__Product__dlm>();
         Boolean hasCompositeDeckBoardPurchase = false;
         Boolean hasBladeProductPurchase = false;
		
        Set<String> pastProductIds = getRecentProductIds(conId);
        if (pastProductIds.isEmpty()) return result;

        List<ssot__Product__dlm> productList = [SELECT ssot__Id__c,ssot__Name__c, ssot__ProductFamily__c,
                                                Product_Features__c,ssot__Description__c,Display_URL__c
                                                FROM ssot__Product__dlm where ssot__Id__c IN :pastProductIds];
        system.debug('productList:'+productList);

        for(ssot__Product__dlm prod : productList){
            
            if (prod.ssot__Name__c == null || prod.ssot__ProductFamily__c == null) {
                continue;
            }
            
             String productName = prod.ssot__Name__c.toLowerCase();
            system.debug('productName:'+productName);
            Boolean isBladeFamily = prod.ssot__ProductFamily__c.equalsIgnoreCase('Blade');
			Boolean isCompositeDeckBoard  = productName.contains('composite') && productName.contains('deck') && productName.contains('board');
			Boolean hasBladeInName  = productName.contains('blade');
            
            if(isCompositeDeckBoard ){
                  hasCompositeDeckBoardPurchase = true;
            }
            system.debug('hasCompositeDeckBoardPurchase:'+hasCompositeDeckBoardPurchase);
            system.debug('isBladeFamily:'+hasCompositeDeckBoardPurchase);
            system.debug('hasBladeInName:'+hasBladeInName);
            // Check product family is 'Blade'
                if (isBladeFamily && hasBladeInName && !isCompositeDeckBoard) {
                 familyBladeProducts.add(prod);
              }
           system.debug('after hasCompositeDeckBoardPurchase:'+hasCompositeDeckBoardPurchase);
            system.debug(' familyBladeProducts:'+familyBladeProducts);
  		  
        }
        system.debug('familyBladeProducts:'+familyBladeProducts);
        if(!familyBladeProducts.isEmpty() && hasCompositeDeckBoardPurchase){
             result.products.addAll(familyBladeProducts);
        }
  			
       system.debug('result:'+result); 
        
        return result;
    } 

          /* =========================================================
       LOGIC 3: ReturnBatteryProductFeature
       ========================================================= */
	public static Response returnBatteryRecomendation(Id contactId){ 
          Response result = new Response();
        if(contactId == null) return result;
        
        Contact contactListId = [Select id,name,accountId from Contact where id =:contactId OR accountId =:contactId limit 1];
        Id conId = contactListId.id;
        system.debug('conId:'+conId);
		
		Set<String> pastBatteryPurchaseSet = new Set<String>();
		List<ssot__Product__dlm> productToolsList = new List<ssot__Product__dlm>();
		
		 Set<String> pastProductIds = getRecentProductIds(conId);
        if (pastProductIds.isEmpty()) return result;
   
        List<ssot__Product__dlm> prodList = [SELECT ssot__Id__c,ssot__Name__c, ssot__ProductFamily__c,
                                                ssot__Description__c,Display_URL__c
                                                FROM ssot__Product__dlm];
								
	    for(ssot__Product__dlm prod:prodList){
			if(pastProductIds != null && pastProductIds.contains(prod.ssot__Id__c)){
				String productname = prod.ssot__Name__c;
			if(prod.ssot__ProductFamily__c == 'Batteries' && productname != null){
				pastBatteryPurchaseSet.add(prod.ssot__Name__c);
			 }
			}
			
			if(prod.ssot__ProductFamily__c == 'Power Tools' || prod.ssot__ProductFamily__c == 'Hand Tools'){
				productToolsList.add(prod);
			}
		}
        system.debug('pastBatteryPurchaseSet:'+pastBatteryPurchaseSet);
		system.debug('productToolsList:'+productToolsList);
		
		if(!pastBatteryPurchaseSet.isEmpty()){
			result.messages.add(
                'Since you are already invested in ' + 
                String.join(new List<String>(pastBatteryPurchaseSet), ', ') + 
                'battery product.'
            );
        } else{
			result.messages.add(
                'You have not purchased any battery product ');
		}
		
        
        if(!productToolsList.isEmpty()){
            result.products.addAll(productToolsList);
        }
		system.debug('result:'+result);

        return result;
		
    }  
    
}