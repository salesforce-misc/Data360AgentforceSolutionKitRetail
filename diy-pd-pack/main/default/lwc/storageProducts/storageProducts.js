import { LightningElement, api } from 'lwc';

export default class StorageProducts extends LightningElement {
    @api value;

    /** If value is wrapper -> return wrapper; if value is [wrapper] -> first */
    get root() {
      console.log('value', this.value);
        if (!this.value) return null;
        return Array.isArray(this.value) ? (this.value[0] ?? null) : this.value;
    }

    /** Show message once (if present in wrapper) */
    get message() {
        console.log('root', this.root);
        return this.root?.message ?? '';
    }

    get hasMessage() {
        return !!this.message;
    }

    /** Extract products array from multiple possible shapes */
    get productsSource() {
        const r = this.root;
        if (!r) return [];

        // ✅ If r.products exists (wrapper shape)
        if (Array.isArray(r.products)) {
            return r.products;
        }

        // ✅ If r.productsJson exists (wrapper with JSON string)
        if (r.productsJson) {
            try {
                const parsed = JSON.parse(r.productsJson);
                return Array.isArray(parsed) ? parsed : [];
            } catch (e) {
                return [];
            }
        }

        // ✅ If root itself is the product (your working scenario)
        // If it looks like a product record/object, treat as single-item list
        if (r.Name || r.name || r.ProductName || r.productName) {
            return [r];
        }

        // ✅ If original value was a pure array of products (working scenario)
        if (Array.isArray(this.value)) {
            return this.value;
        }

        return [];
    }

    /** Normalize Agentforce value to array that template can iterate */
    get products() {
        const arr = this.productsSource;

        return arr.map((p, idx) => {
            // support both your product key styles
            const name =
                p.ProductName ?? p.productName ?? p.Name ?? p.name ?? '';

            const description =
                p.Description ?? p.description ?? p.productDescription ?? '';

            const displayUrl =
                p.DisplayUrl ?? p.displayUrl ?? p.imageUrl ?? p.ImageUrl ?? p.image ?? p.image_src ?? '';

            // clickable link (fallbacks)
            const customUrl =
                p.productUrl ?? p.URL__c ?? p.url ?? p.Url ?? displayUrl ?? '';

            const imageUrl = displayUrl || customUrl || '';

            return {
                key: p.Id ?? p.id ?? `${name || 'product'}-${idx}`,
                name,
                imageUrl,
                imageRedirectUrl: customUrl || imageUrl,
                url: customUrl || imageUrl,
                description
            };
        }).filter(x => x.name || x.imageUrl || x.description);
    }

    get hasProducts() {
      
        return this.products.length > 0;
    }
}