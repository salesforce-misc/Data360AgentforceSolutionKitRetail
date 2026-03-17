public with sharing class ValidateContactContext {

    public class Request {
        @InvocableVariable(required=false)
        public Id contactId;
    }

    public class Response {
        @InvocableVariable
        public Id contactId;

        @InvocableVariable
        public Boolean isGuest;
    }

    @InvocableMethod
    public static List<Response> validate(List<Request> requests) {

        List<Response> results = new List<Response>();

        for (Request req : requests) {

            Response res = new Response();

            Boolean validContact = false;

            if (req != null && req.contactId != null) {
                try {
                    validContact = req.contactId.getSObjectType() == Contact.SObjectType;
                } catch (Exception e) {
                    validContact = false;
                }
            }

            if (validContact) {
                res.contactId = req.contactId;
                res.isGuest = false;
            } else {
                res.contactId = null;
                res.isGuest = true;
            }

            results.add(res);
        }

        return results;
    }
}