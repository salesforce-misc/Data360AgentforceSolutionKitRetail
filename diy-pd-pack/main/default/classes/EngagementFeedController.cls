public with sharing class EngagementFeedController {
    
    public static String getSessionIdFromVFPage()
     {
         if (Test.isRunningTest()) {
        return 'MY_SESSION_ID'; // Return dummy session ID in tests
    	}
        //String SessionId;
         PageReference visualforcePage = Page.EPSessionIdHelper;
         String content = visualforcePage.getContent().toString();
         Integer s = content.indexOf('Start_Of_Session_Id') + 'Start_Of_Session_Id'.length(),
             e = content.indexOf('End_Of_Session_Id');
         return content.substring(s, e);

    }

    /* =========================================================
       Wrapper Returned to LWC
    ========================================================= */

    public class FeedItem {

        @AuraEnabled public String id;
        @AuraEnabled public String title;
        @AuraEnabled public String description;
        @AuraEnabled public String eventTime;
        @AuraEnabled public String icon;
        @AuraEnabled public String color;
    }


    /* =========================================================
       Main Method Called From LWC
    ========================================================= */

    @AuraEnabled(cacheable=true)
    public static List<FeedItem> getEngagementFeed(String accountId) {

        /* =========================
           1. Get Contact Id
        ========================= */

        List<Contact> contacts = [
            SELECT Id
            FROM Contact
            WHERE AccountId = :accountId
            ORDER BY CreatedDate ASC
            LIMIT 1
        ];

        // No Contact = No Feed
        if (contacts.isEmpty()) {
            return new List<FeedItem>();
        }

        String contactId = contacts[0].Id;


        /* =========================
           2. Build SQL (Your Query)
        ========================= */

        String sql =
            'SELECT ' +
            ' ssot__Individual__dlm.ssot__Id__c as individualid__c,' +
            ' ssot__Individual__dlm.CIN__c as cin__c,' +
            ' Customer_Engagement_Feed__dlm.Category__c as category__c,' +
            ' Customer_Engagement_Feed__dlm.Description__c as description__c,' +
            ' Customer_Engagement_Feed__dlm.EventDate__c as eventdate__c ' +

            ' FROM ( ' +
            '   SELECT UnifiedssotIndividualReal__dlm.ssot__Id__c as unifiedindividualid__c ' +
            '   FROM UnifiedssotIndividualReal__dlm ' +
            '   JOIN UnifiedLinkssotIndividualReal__dlm ' +
            '     ON UnifiedssotIndividualReal__dlm.ssot__Id__c = ' +
            '        UnifiedLinkssotIndividualReal__dlm.UnifiedRecordId__c ' +
            '   WHERE UnifiedLinkssotIndividualReal__dlm.SourceRecordId__c = \'' +
                String.escapeSingleQuotes(contactId) + '\'' +
            ' ) SUBQ ' +

            ' JOIN UnifiedLinkssotIndividualReal__dlm ' +
            '   ON UnifiedLinkssotIndividualReal__dlm.UnifiedRecordId__c = ' +
            '      SUBQ.unifiedindividualid__c ' +

            ' JOIN ssot__Individual__dlm ' +
            '   ON UnifiedLinkssotIndividualReal__dlm.SourceRecordId__c = ' +
            '      ssot__Individual__dlm.ssot__Id__c ' +

            ' JOIN Customer_Engagement_Feed__dlm ' +
            '   ON ssot__Individual__dlm.CIN__c = ' +
            '      Customer_Engagement_Feed__dlm.CIN__c';


        /* =========================
           3. Request Body
        ========================= */

        Map<String, Object> bodyMap = new Map<String, Object>();
        bodyMap.put('sql', sql);

        String requestBody = JSON.serialize(bodyMap);
		System.debug('## requestBody = '+requestBody);
		String sid = UserInfo.getSessionId();
		System.debug('## sid = '+sid);
        /* =========================
           4. HTTP Callout
        ========================= */
		//String endpoint = '';
		//String orgURL = System.URL.getOrgDomainUrl().toExtenralForm();
        HttpRequest req = new HttpRequest();

        req.setEndpoint(
            System.URL.getOrgDomainUrl().toExternalForm() + '/services/data/v62.0/ssot/queryv2'
        );
		if(!Test.isRunningTest()){
                req.setHeader('Authorization', 'Bearer ' + getSessionIdFromVFPage());
            }
        req.setMethod('POST');
        req.setHeader('Content-Type', 'application/json');
        req.setTimeout(20000);

        req.setBody(requestBody);


        Http http = new Http();
        HttpResponse res = http.send(req);
		System.debug('## getStatusCode = '+res.getStatusCode());
		System.debug('## getBody = '+res.getBody());
        if (res.getStatusCode() == 201 || res.getStatusCode() == 200) {
            System.debug('## Parsed Response = '+parseResponse(res.getBody()));
            return parseResponse(res.getBody());
            
        }else{
            throw new AuraHandledException(
                'Data Cloud Call Failed (' +
                res.getStatusCode() + '): ' +
                res.getBody()
            );
        }
    }


    /* =========================================================
       Parse Data Cloud Response
    ========================================================= */

    private static List<FeedItem> parseResponse(String body) {

        Map<String, Object> json =
            (Map<String, Object>) JSON.deserializeUntyped(body);

        List<Object> rows =
            (List<Object>) json.get('data');

        List<FeedItem> results = new List<FeedItem>();


        if (rows == null) {
            return results;
        }


        for (Object rowObj : rows) {

            List<Object> row = (List<Object>) rowObj;

            /*
              API Response Order:
              [0] individualId
              [1] cin
              [2] category (Title)
              [3] description
              [4] eventdate
            */

            FeedItem item = new FeedItem();

            item.id = String.valueOf(Crypto.getRandomLong());

            item.title = (String) row[2];
            item.description = (String) row[3];

            item.eventTime = formatDate(
                (String) row[4]
            );

            mapIconAndColor(item);

            results.add(item);
        }

        return results;
    }


    /* =========================================================
       Icon + Color Mapper
    ========================================================= */

    private static void mapIconAndColor(FeedItem item) {

        if (item.title == null) {
            item.icon = 'utility:trending';
            item.color = '#0176d3';
            return;
        }


        String t = item.title.toLowerCase();


        if (t.contains('sms')) {

            item.icon = 'utility:chat';
            item.color = '#2e844a';

        }
        else if (t.contains('visit')) {

            item.icon = 'utility:preview';
            item.color = '#ba0517';

        }
        else if (t.contains('segment')) {

            item.icon = 'utility:groups';
            item.color = '#ba0517';

        }
        else if (t.contains('drop')) {

            item.icon = 'utility:warning';
            item.color = '#ea001e';

        }
        else {

            item.icon = 'utility:trending';
            item.color = '#0176d3';
        }
    }


    /* =========================================================
       Date Formatter
       "2026-01-26 13:45:11.000 UTC"
       → "1:45PM | Jan 26"
    ========================================================= */

    private static String formatDate(String utc) {

        if (String.isBlank(utc)) {
            return '';
        }

        // Remove " UTC"
        String clean = utc.replace(' UTC', '');

        Datetime dt = Datetime.valueOfGmt(clean);

        return dt.format('h:mma | MMM d');
    }

}