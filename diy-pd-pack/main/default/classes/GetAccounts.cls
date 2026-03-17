public with sharing class GetAccounts {
    @AuraEnabled(cacheable=true)
    public static Account getAccountDetails(Id accountId) {
        Account accountDetails = [SELECT Id, Name,BillingCity,BillingState,BillingPostalCode,BillingStreet, PersonContactId,
                                        (SELECT Lifetime_Value__c, Average_Purchase_Value__c,Customer_StorePreference__c,Customer_ProjectFrequency__c,Customer_FamilySizes__c,Customer_GarageSize__c,Customer_OwnershipStatus__c,Customer_PurchaseFrequency__c,Customer_SkillLevel__c,Customer_ResidenceType__c,Customer_Seasonality__c,
                                           Average_Order_Value__c,Customer_Since__c 
                                           FROM Contacts 
                                           WHERE AccountId = :accountId 
                                           LIMIT 1)
                                      FROM Account
                                      WHERE Id = :accountId
                                      LIMIT 1];
    
            return accountDetails;
        }
    }