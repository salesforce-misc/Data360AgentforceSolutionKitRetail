global  class GenericProductInvocable {

    // ---- Input wrapper (for Flow/Invocable) ----
    global class Request {
        @InvocableVariable(required=true)
        global String requestType; // PROMOTION | SEASONAL | PAST_ORDERS

         @InvocableVariable
        global Id contactId;
    }

    // ---- Response wrapper for Prompt Templates ----
    global class promptResponse {
         @InvocableVariable
        global String Prompt; // Single flattened string for Copilot/Prompt Template
    }

    // ---- Invocable Method (Prompt-friendly) ----
    @InvocableMethod(label='Generic Product Engine' description='Returns a single Prompt string per request for Prompt Templates' category='Prompt')
   global static List<promptResponse> invoke(List<Request> requests) {

       List<promptResponse> promptResponses = new List<promptResponse>();
        promptResponse pr = new promptResponse();
         for(Request req : requests){
            GenericProductService.Response res;
			if(req.requestType == 'PROMOTION'){
                res = GenericProductService.customerPromotionEligibility(req.contactId);
            }
            if(req.requestType == 'STORAGE_PRODUCTS'){
                res = GenericProductService.returnStorageRecommendation(req.contactId);
            } 
             
             if(req.requestType == 'BLADE_PRODUCTS'){
                res = GenericProductService.returnBladeRecomendation(req.contactId);
            } 
             
           if(req.requestType == 'BATTERY_PRODUCTS'){
                res = GenericProductService.returnBatteryRecomendation(req.contactId);
            }

            // Convert Response into a single prompt string
            String promptText = buildPromptFromResponse(res);

           
            pr.Prompt = promptText;
            promptResponses.add(pr);
        }

        return promptResponses;
    }
    
    /* ===== Convert Response into a single prompt string ===== */
    private static String buildPromptFromResponse(GenericProductService.Response res){
        List<String> parts = new List<String>();

        if(res != null){
        if(res.messages.isEmpty()){
            // Add a space if messages are empty
            parts.add(' '); 
        } else {
            parts.add(String.join(res.messages, '\n'));
        }
            
            if(res.products.isEmpty()){
                parts.add('Recommended Products:\n '); // Placeholder if no products

            }
        else{
          List<String> productLines = new List<String>();
            for(ssot__Product__dlm p : res.products){

                String line = '- ' + p.ssot__Name__c;
                if(p.ssot__Description__c != null) line += ': ' + p.ssot__Description__c;
                if(p.Display_URL__c != null) line += '|' + p.Display_URL__c;
                productLines.add(line);
            }
            parts.add('Recommended Products:\n' + String.join(productLines, '\n'));
        }
      }
        if(parts.isEmpty()){
            return 'No product recommendations available at this time.';
        }

        return String.join(parts, '\n\n');
    }

}