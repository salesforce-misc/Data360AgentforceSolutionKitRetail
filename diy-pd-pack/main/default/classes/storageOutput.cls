public class storageOutput {
	@AuraEnabled @InvocableVariable
    public String message;

    @AuraEnabled @InvocableVariable 
    public String productsJson; // JSON array string (products list)
}