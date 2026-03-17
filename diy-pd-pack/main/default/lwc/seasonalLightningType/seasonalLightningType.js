import { LightningElement, api } from 'lwc';

export default class SeasonalLightningType extends LightningElement {
    @api value;

    /** Find wrapper reliably: if array, find element that has message/messages/productsJson/products */
    get root() {
        if (!this.value) return null;

        if (Array.isArray(this.value)) {
            // Find wrapper anywhere in the array
            return this.value.find(x =>
                x &&
                (typeof x.message === 'string' ||
                 Array.isArray(x.messages) ||
                 x.productsJson ||
                 Array.isArray(x.products))
            ) || null;
        }

        return this.value;
    }

    /** Show message once (supports message:string OR messages:list) */
    get message() {
        const r = this.root;
        if (!r) return '';

        // Case 1: message string
        if (typeof r.message === 'string' && r.message.trim()) return r.message;

        // Case 2: messages list
        if (Array.isArray(r.messages) && r.messages.length) {
            return r.messages.filter(Boolean).join('\n');
        }

        return '';
    }

    get hasMessage() {
        return !!this.message;
    }

    /** Extract products array from multiple possible shapes */
    get productsSource() {
        const r = this.root;

        // 1) wrapper.products
        if (r && Array.isArray(r.products)) return r.products;

        // 2) wrapper.productsJson
        if (r && r.productsJson) {
            try {
                const parsed = JSON.parse(r.productsJson);
                return Array.isArray(parsed) ? parsed : [];
            } catch (e) {
                return [];
            }
        }

        // 3) If original value is array of products (no wrapper)
        if (Array.isArray(this.value)) {
            return this.value.filter(x => x && (x.Name || x.name || x.ProductName || x.productName));
        }

        // 4) Single product object
        if (r && (r.Name || r.name || r.ProductName || r.productName)) return [r];

        return [];
    }

    /** Normalize products for UI */
    get products() {
        const arr = this.productsSource;

        return arr.map((p, idx) => {
            const name = p.ProductName ?? p.productName ?? p.Name ?? p.name ?? '';

            const description =
                p.Description ?? p.description ?? p.productDescription ?? '';

            const displayUrl =
                p.DisplayUrl ?? p.displayUrl ?? p.imageUrl ?? p.ImageUrl ?? p.image ?? p.image_src ?? p.Display_URL__c ?? '';

            const customUrl =
                p.productUrl ?? p.URL__c ?? p.url ?? p.Url ?? displayUrl ?? '';

            const imageUrl = displayUrl || customUrl || '';

            return {
                key: p.Id ?? p.id ?? p.productId ?? `${name || 'product'}-${idx}`,
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