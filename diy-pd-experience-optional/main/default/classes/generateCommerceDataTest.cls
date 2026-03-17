@IsTest
public class generateCommerceDataTest {
    
    @TestSetup
    static void setupTestData() {
        
        // Create Product Catalog
        ProductCatalog catalog = new ProductCatalog(
            Name = 'DIYStorefront Catalog'
        );
        insert catalog;
        
        // Create default "Products" category (used in code)
        ProductCategory defaultCategory = new ProductCategory(
            Name = 'Products',
            IsNavigational = true,
            CatalogId = catalog.Id
        );
        insert defaultCategory;
        
        // Create Commerce Entitlement Policy
        CommerceEntitlementPolicy policy = new CommerceEntitlementPolicy(
            Name = 'All Access for DIYStorefront'
        );
        insert policy;
        
        // Create Products (must match Family values used in mapping)
        List<Product2> products = new List<Product2>{
            new Product2(Name='Winter Item', Family='Winter Maintenance', IsActive=true, DisplayUrl='http://test.com/1'),
            new Product2(Name='Safety Item', Family='Safety Gear', IsActive=true, DisplayUrl='http://test.com/2'),
            new Product2(Name='Storage Item', Family='Storage', IsActive=true, DisplayUrl='http://test.com/3')
        };
        insert products;
        
        // Create old pricebook
        Pricebook2 oldPB = new Pricebook2(
            Name = 'DIYStore Custom Price Book',
            IsActive = true
        );
        insert oldPB;
        
        // Create new storefront pricebook
        Pricebook2 newPB = new Pricebook2(
            Name = 'DIYStorefront Price Book 2026',
            IsActive = true
        );
        insert newPB;
        
        // Standard pricebook entry required before custom pricebook entry
        Id standardPBId = Test.getStandardPricebookId();
        
        List<PricebookEntry> stdEntries = new List<PricebookEntry>();
        for(Product2 p : products){
            stdEntries.add(new PricebookEntry(
                Pricebook2Id = standardPBId,
                Product2Id = p.Id,
                UnitPrice = 100,
                IsActive = true
            ));
        }
        insert stdEntries;
        
        // Add entries to old pricebook
        List<PricebookEntry> oldEntries = new List<PricebookEntry>();
        for(Product2 p : products){
            oldEntries.add(new PricebookEntry(
                Pricebook2Id = oldPB.Id,
                Product2Id = p.Id,
                UnitPrice = 150,
                IsActive = true,
                UseStandardPrice = false
            ));
        }
        insert oldEntries;
    }
    
    @IsTest
    static void testCreateCommercePolicy() {
        
        Test.startTest();
        generateCommerceData.createCommercePolicy();
        Test.stopTest();
        
        // Validate CommerceEntitlementProduct created
        List<CommerceEntitlementProduct> policies =
            [SELECT Id FROM CommerceEntitlementProduct];
        System.assert(policies.size() > 0, 'CommerceEntitlementProduct records should be created');
        
        // Validate ProductCategory created
        List<ProductCategory> categories =
            [SELECT Id FROM ProductCategory WHERE Name = 'Seasonal'];
        System.assert(categories.size() > 0, 'Categories should be created');
        
        // Validate ProductCategoryProduct created
        List<ProductCategoryProduct> pcp =
            [SELECT Id FROM ProductCategoryProduct];
        System.assert(pcp.size() > 0, 'ProductCategoryProduct should be created');
    }
    
    @IsTest
    static void testInsertionPricebookStore() {
        
        Test.startTest();
        generateCommerceData.insertionPricebookStore();
        Test.stopTest();
        
        // Verify entries inserted into storefront pricebook
        Pricebook2 newPB = [SELECT Id FROM Pricebook2 WHERE Name LIKE 'DIYStorefront Price Book%' LIMIT 1];
        
        List<PricebookEntry> newEntries =
            [SELECT Id FROM PricebookEntry WHERE Pricebook2Id = :newPB.Id];
        
        System.assert(newEntries.size() > 0, 'New pricebook entries should be created');
    }
}