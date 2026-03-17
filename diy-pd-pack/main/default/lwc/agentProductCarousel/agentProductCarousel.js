import { LightningElement, api } from 'lwc';

export default class AgentProductList extends LightningElement {
    
@api value;

    /** Build a map: productName -> promo message(s) */
    get promoByProductName() {
        const map = new Map();

        const fullMessage = this.value?.message || '';
        if (!fullMessage) return map;

        // Split into lines and pick only the promo lines
        const lines = fullMessage
            .split('\n')
            .map(l => l.trim())
            .filter(Boolean);

        for (const line of lines) {
            // Match: "Product Name has discount of: promo text"
            const m = line.match(/^(.*?)\s+has discount of:\s+(.*)$/i);
            if (!m) continue;

            const prodName = m[1].trim();
            const promoText = m[2].trim();

            // If multiple promos per product, join them
            if (map.has(prodName)) {
                map.set(prodName, `${map.get(prodName)}\n${promoText}`);
            } else {
                map.set(prodName, promoText);
            }
        }

        return map;
    }

    /** Products list from productsJson (Flow output) */
    get products() {
        if (!this.value) return [];

        let raw = [];
        try {
            raw = this.value.productsJson ? JSON.parse(this.value.productsJson) : [];
        } catch (e) {
            raw = [];
        }

        const promoMap = this.promoByProductName;

        return (Array.isArray(raw) ? raw : [raw]).map((p, idx) => {
            const name = p.name ?? p.Name ?? '';

            const customUrl =
                p.productUrl ?? p.URL__c ?? p.displayUrl ?? p.url ?? '';

            const imageUrlCandidate =
                p.ImageUrl ?? p.imageUrl ?? p.image ?? p.image_src ?? null;

            const imageUrl = imageUrlCandidate || customUrl || '';

            return {
                key: p.productId ?? p.Id ?? p.id ?? `${name || 'product'}-${idx}`,
                name,
                description: p.description ?? p.Description ?? '',
                imageUrl,
                imageRedirectUrl: customUrl,
                url: customUrl,

                // ✅ promo message for this product name (if found)
                promoMessage: promoMap.get(name) || ''
            };
        });
    }

    get hasProducts() {
        return this.products.length > 0;
    }

    /** Optional: show only the header line at top (not the promo lines) */
    get headerMessage() {
        const fullMessage = this.value?.message || '';
        if (!fullMessage) return '';

        // keep only non-promo lines (e.g., the greeting line)
        const headerLines = fullMessage
            .split('\n')
            .map(l => l.trim())
            .filter(Boolean)
            .filter(l => !/has discount of:/i.test(l));

        return headerLines.join('\n');
    }

}