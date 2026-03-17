public class PromotionOutput {
	 @AuraEnabled @InvocableVariable
    public String message;

    @AuraEnabled @InvocableVariable 
    public String productsJson; // JSON array string (products list)
}