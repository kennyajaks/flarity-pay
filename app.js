// ================= FLARITY PAY CLIENT-SIDE ENGINE =================

// Coston2 RPC configuration
const COSTON2_RPC = "https://coston2-api.flare.network/ext/C/rpc";
const FTSO_V2_ADDRESS = "0x7BDE3Df0624114eDB3A67dFe6753e62f4e7c1d20";

// FTSOv2 Feed IDs (21-bytes hex)
const FEED_IDS = {
    FLR: "0x01464c522f55534400000000000000000000000000",
    BTC: "0x014254432f55534400000000000000000000000000",
    XRP: "0x015852502f55534400000000000000000000000000",
    DOGE: "0x01444f47452f555344000000000000000000000000"
};

// Simplified ABI for FTSOv2 contract
const FTSO_ABI = [
    "function getFeedById(bytes21 _feedId) external view returns (uint256 value, int8 decimals, uint64 timestamp)"
];

// App Global State
const state = {
    cart: [],
    listings: [
        {
            id: 1,
            seller: "0x5336E1e04A1d5F69b86e057b7D05621cBcc645b0", // Platform store / Admin
            title: "Flarity Ledger Vault",
            description: "Advanced hardware credential vault secured by off-chain Trusted Execution Environment keys.",
            priceUSD: 149.00,
            imageUrl: "images/wallet.jpg",
            type: "Product",
            active: true
        },
        {
            id: 2,
            seller: "0x5336E1e04A1d5F69b86e057b7D05621cBcc645b0",
            title: "Cyberpunk Mechanical Keyboard",
            description: "Tactile keyboard with glowing custom keys, obsidian build, and responsive switches.",
            priceUSD: 89.00,
            imageUrl: "images/keyboard.jpg",
            type: "Product",
            active: true
        },
        {
            id: 3,
            seller: "0x123f123456789012345678901234567890123456", // Seller A
            title: "Solidity Code Security Audit",
            description: "Complete security check of your smart contracts including a detailed vulnerability audit report.",
            priceUSD: 299.00,
            imageUrl: "https://images.unsplash.com/photo-1526374965328-7f61d4dc18c5?auto=format&fit=crop&w=600&q=80",
            type: "Service",
            active: true
        },
        {
            id: 4,
            seller: "0x987f654321098765432109876543210987654321", // Seller B
            title: "Dapp Frontend Development",
            description: "Premium glassmorphic user interface development with ethers.js or wagmi wallet connectivity.",
            priceUSD: 899.00,
            imageUrl: "images/workstation.jpg",
            type: "Service",
            active: true
        }
    ],
    reviews: {
        "0x5336E1e04A1d5F69b86e057b7D05621cBcc645b0": [
            { buyer: "0x3A2b...dE89", rating: 5, comment: "Super fast transaction verification and high quality hardware device!", timestamp: "1 hour ago" }
        ],
        "0x123f123456789012345678901234567890123456": [
            { buyer: "0x789F...66aa", rating: 5, comment: "Audited our token contracts, extremely thorough audit reports.", timestamp: "1 day ago" }
        ],
        "0x987f654321098765432109876543210987654321": [
            { buyer: "0xbc8e...44ff", rating: 4, comment: "Excellent frontend styles, highly recommended coder.", timestamp: "3 days ago" }
        ]
    },
    verifiedPurchases: {
        // Track local purchase history to satisfy verified buyer checks: "buyerAddress_sellerAddress": true
        "shopperAddress_0x5336E1e04A1d5F69b86e057b7D05621cBcc645b0": true // Default pre-credited for testing
    },
    selectedReviewSeller: "0x5336E1e04A1d5F69b86e057b7D05621cBcc645b0",
    interactiveRating: 5,
    activeFilter: "all",
    prices: {
        FLR: 0.0182,
        XRP: 0.5840,
        BTC: 58240.00,
        DOGE: 0.1140
    },
    balances: {
        wallet: {
            XRP: 12500.00,
            BTC: 1.4850,
            DOGE: 42000.00
        },
        merchant: {
            revenue: 1438.00,
            FLR: 4521.80,
            WFLR: 15000.00,
            FXRP: 2100.00,
            FBTC: 0.0450,
            FDOGE: 8500.00
        }
    },
    costonBlockHeight: 12450890,
    activeInvoice: null,
    ledger: [
        { id: "#8024", cryptoPaid: "255.13 XRP", fassetsMinted: "254.87 FXRP", chain: "XRPL", chainClass: "xrp-color", status: "Verified", time: "10 mins ago" },
        { id: "#8023", cryptoPaid: "780.70 DOGE", fassetsMinted: "779.92 FDOGE", chain: "Dogecoin", chainClass: "doge-color", status: "Verified", time: "1 hour ago" }
    ],
    ethersProvider: null,
    ftsoContract: null,
    isOnline: false
};

// Target addresses for simulated external chains
const DESTINATION_ADDRESSES = {
    XRP: "rFlarityPayAgentAddressCoston2TestnetXRPLXXXXXXXXX",
    BTC: "tb1qflaritypayagentbtcaddresscoston2XXXXXXXXX",
    DOGE: "Dflaritypayagentdogeaddresscoston2XXXXXXXXX"
};

// ================= INITIALIZATION & SETUP =================

document.addEventListener("DOMContentLoaded", () => {
    initTabs();
    initCart();
    initWeb3();
    initWrapping();
    initVisualizer();
    renderLedger();
    
    // Marketplace upgrades
    initMarketplaceFilter();
    initListingForm();
    initReviewsSystem();
    renderMarketplaceListings();
    renderReviews();

    // Periodically update network status and block numbers
    setInterval(updateNetworkData, 3000);
});

// Setup Tab Navigation
function initTabs() {
    const tabs = document.querySelectorAll(".nav-tab");
    tabs.forEach(tab => {
        tab.addEventListener("click", () => {
            tabs.forEach(t => t.classList.remove("active"));
            tab.classList.add("active");
            
            const target = tab.getAttribute("data-target");
            const contents = document.querySelectorAll(".tab-content");
            contents.forEach(content => {
                content.classList.remove("active");
                if (content.id === target) {
                    content.classList.add("active");
                }
            });
        });
    });
}

// Connect to Coston2 Testnet RPC
async function initWeb3() {
    const blockEl = document.getElementById("current-block-height");
    const rpcStatusEl = document.getElementById("rpc-status");
    
    try {
        state.ethersProvider = new ethers.providers.JsonRpcProvider(COSTON2_RPC);
        state.ftsoContract = new ethers.Contract(FTSO_V2_ADDRESS, FTSO_ABI, state.ethersProvider);
        
        const block = await state.ethersProvider.getBlockNumber();
        state.costonBlockHeight = block;
        blockEl.textContent = block.toLocaleString();
        state.isOnline = true;
        rpcStatusEl.textContent = "Connected";
        rpcStatusEl.className = "text-green";
        
        await fetchFTSOPrices();
    } catch (e) {
        console.warn("Unable to connect to Coston2 RPC. Using simulated local feed: ", e);
        state.isOnline = false;
        rpcStatusEl.textContent = "Simulated";
        rpcStatusEl.className = "text-orange";
        blockEl.textContent = state.costonBlockHeight.toLocaleString();
        
        simulatePrices();
    }
}

// Fetch prices from Coston2 FTSO contract
async function fetchFTSOPrices() {
    if (!state.isOnline || !state.ftsoContract) return;
    
    try {
        for (const token of Object.keys(FEED_IDS)) {
            const feedId = FEED_IDS[token];
            const data = await state.ftsoContract.getFeedById(feedId);
            
            const rawValue = data.value.toString();
            const decimals = data.decimals;
            const price = parseFloat(rawValue) / Math.pow(10, decimals);
            
            state.prices[token] = price;
            updatePriceUI(token, price);
        }
    } catch (e) {
        console.error("Error fetching FTSOv2 price feeds:", e);
    }
}

// Fallback: simulate local fluctuations
function simulatePrices() {
    setInterval(() => {
        state.costonBlockHeight += 1;
        document.getElementById("current-block-height").textContent = state.costonBlockHeight.toLocaleString();
        
        const assets = ["FLR", "XRP", "BTC", "DOGE"];
        assets.forEach(asset => {
            const current = state.prices[asset];
            const percentChange = (Math.random() - 0.5) * 0.001; // max 0.1% change
            state.prices[asset] = current * (1 + percentChange);
            updatePriceUI(asset, state.prices[asset]);
        });
        
        if (state.activeInvoice) {
            updateModalCalculations();
        }
    }, 1800);
}

// Update network metrics periodically
async function updateNetworkData() {
    if (state.isOnline && state.ethersProvider) {
        try {
            const block = await state.ethersProvider.getBlockNumber();
            state.costonBlockHeight = block;
            document.getElementById("current-block-height").textContent = block.toLocaleString();
            await fetchFTSOPrices();
        } catch (e) {
            console.warn("RPC update failed:", e);
        }
    } else {
        state.costonBlockHeight += 1;
        document.getElementById("current-block-height").textContent = state.costonBlockHeight.toLocaleString();
        
        const assets = ["FLR", "XRP", "BTC", "DOGE"];
        assets.forEach(asset => {
            const current = state.prices[asset];
            const percentChange = (Math.random() - 0.5) * 0.001;
            state.prices[asset] = current * (1 + percentChange);
            updatePriceUI(asset, state.prices[asset]);
        });
    }
    
    if (state.activeInvoice) {
        updateModalCalculations();
    }
}

function updatePriceUI(token, price) {
    const priceEl = document.getElementById(`price-${token}`);
    const timeEl = document.getElementById(`time-${token}`);
    
    if (priceEl) {
        let decimals = 4;
        if (price > 1000) decimals = 2;
        priceEl.textContent = `$${price.toFixed(decimals)}`;
    }
    if (timeEl) {
        timeEl.textContent = "just now";
    }
}

// ================= SHOPPING CART & STOREFRONT =================

function initCart() {
    // Add dynamically delegated listener since cards are generated at runtime
    const grid = document.getElementById("marketplace-listings-grid");
    grid.addEventListener("click", (e) => {
        const btn = e.target.closest(".btn-add-cart");
        if (!btn) return;
        
        const card = btn.closest(".premium-product-card");
        const id = parseInt(card.getAttribute("data-id"));
        const listing = state.listings.find(l => l.id === id);
        
        if (listing) {
            addToCart(listing.id, listing.title, listing.priceUSD, listing.seller);
            animateCartBtn(btn);
        }
    });

    // Modal control listeners
    document.getElementById("btn-checkout").addEventListener("click", openCheckoutModal);
    document.getElementById("btn-close-modal").addEventListener("click", () => {
        closeCheckoutModal();
    });
    document.getElementById("btn-modal-pay-simulate").addEventListener("click", routeToWalletPayment);
    
    // Copy buttons
    document.getElementById("btn-copy-address").addEventListener("click", () => {
        copyText("merchant-destination-address");
    });
    document.getElementById("btn-copy-ref").addEventListener("click", () => {
        copyText("payment-reference-hex");
    });
    
    // Currency cards in checkout
    const currencyCards = document.querySelectorAll(".asset-selector-card");
    currencyCards.forEach(card => {
        card.addEventListener("click", () => {
            currencyCards.forEach(c => c.classList.remove("active"));
            card.classList.add("active");
            
            const currency = card.getAttribute("data-currency");
            if (state.activeInvoice) {
                state.activeInvoice.currency = currency;
                updateModalCalculations();
            }
        });
    });
}

function addToCart(id, name, price, seller) {
    const existing = state.cart.find(item => item.id === id);
    if (existing) {
        existing.qty += 1;
    } else {
        state.cart.push({ id, name, price, qty: 1, seller });
    }
    
    updateCartUI();
}

function removeFromCart(id) {
    state.cart = state.cart.filter(item => item.id !== id);
    updateCartUI();
}

function updateCartUI() {
    const listEl = document.getElementById("cart-items-list");
    const countEl = document.getElementById("cart-count");
    const totalEl = document.getElementById("cart-total");
    const checkoutBtn = document.getElementById("btn-checkout");
    
    listEl.innerHTML = "";
    
    let totalItems = 0;
    let totalPrice = 0;
    
    if (state.cart.length === 0) {
        listEl.innerHTML = `
            <div class="basket-empty-state">
                <i class="ri-shopping-basket-2-line"></i>
                <p>Your shopping basket is empty</p>
            </div>
        `;
        checkoutBtn.disabled = true;
    } else {
        state.cart.forEach(item => {
            totalItems += item.qty;
            totalPrice += item.price * item.qty;
            
            const div = document.createElement("div");
            div.className = "cart-item";
            div.innerHTML = `
                <div class="info">
                    <h4>${item.name}</h4>
                    <span>${item.qty} × $${item.price.toFixed(2)}</span>
                </div>
                <button class="remove-btn" onclick="removeFromCart(${item.id})">
                    <i class="ri-delete-bin-6-line"></i>
                </button>
            `;
            listEl.appendChild(div);
        });
        checkoutBtn.disabled = false;
    }
    
    countEl.textContent = `${totalItems} ${totalItems === 1 ? 'item' : 'items'}`;
    totalEl.textContent = `$${totalPrice.toFixed(2)}`;
}

function animateCartBtn(btn) {
    const originalText = btn.innerHTML;
    btn.innerHTML = `<i class="ri-checkbox-circle-line"></i> Added`;
    btn.style.borderColor = "var(--color-green)";
    btn.style.color = "var(--color-green)";
    btn.style.background = "rgba(43, 173, 10, 0.1)";
    
    setTimeout(() => {
        btn.innerHTML = originalText;
        btn.style.borderColor = "";
        btn.style.color = "";
        btn.style.background = "";
    }, 1500);
}

window.removeFromCart = removeFromCart;

// ================= DYNAMIC MARKETPLACE RENDERERS & FILTERS =================

function initMarketplaceFilter() {
    const filterBtns = document.querySelectorAll(".filter-btn");
    filterBtns.forEach(btn => {
        btn.addEventListener("click", () => {
            filterBtns.forEach(b => b.classList.remove("active"));
            btn.classList.add("active");
            state.activeFilter = btn.getAttribute("data-filter");
            renderMarketplaceListings();
        });
    });
}

function renderMarketplaceListings() {
    const grid = document.getElementById("marketplace-listings-grid");
    grid.innerHTML = "";
    
    const filtered = state.listings.filter(listing => {
        if (!listing.active) return false;
        if (state.activeFilter === "all") return true;
        return listing.type === state.activeFilter;
    });
    
    if (filtered.length === 0) {
        grid.innerHTML = `
            <div class="no-items-state">
                <i class="ri-search-line"></i>
                <p>No listings registered in this category.</p>
            </div>
        `;
        return;
    }
    
    filtered.forEach(item => {
        const card = document.createElement("div");
        card.className = "premium-product-card";
        card.setAttribute("data-id", item.id);
        card.setAttribute("data-name", item.title);
        card.setAttribute("data-price", item.priceUSD);
        
        // Custom badges for categories
        const badgeText = item.type === "Service" ? "Service" : "TEE Hardware";
        const badgeClass = item.type === "Service" ? "badge-service" : "badge-feature";
        const badgeIcon = item.type === "Service" ? "ri-tools-line" : "ri-instance-line";
        
        // Calculate stars average dynamically
        const sellerReviews = state.reviews[item.seller] || [];
        const reviewsCount = sellerReviews.length;
        let averageStarsStr = "No reviews";
        if (reviewsCount > 0) {
            const sum = sellerReviews.reduce((acc, curr) => acc + curr.rating, 0);
            averageStarsStr = `${(sum / reviewsCount).toFixed(1)} ★`;
        }

        // Auto generated abstract background if no image is present
        const imgSrc = item.imageUrl || `https://images.unsplash.com/photo-1618005182384-a83a8bd57fbe?auto=format&fit=crop&w=600&q=80`;

        card.innerHTML = `
            <div class="card-image-box">
                <img src="${imgSrc}" alt="${item.title}">
                <span class="${badgeClass}"><i class="${badgeIcon}"></i> ${badgeText}</span>
            </div>
            <div class="card-details">
                <div class="card-seller-row">
                    <span class="seller-address-label"><i class="ri-shield-user-line"></i> ${item.seller.substring(0, 6)}...${item.seller.substring(38)}</span>
                    <span class="seller-stars-badge"><i class="ri-star-fill text-orange"></i> ${averageStarsStr}</span>
                </div>
                <h3 class="product-title">${item.title}</h3>
                <p class="product-desc">${item.description}</p>
                <div class="card-pricing-footer">
                    <span class="product-price">$${item.priceUSD.toFixed(2)}</span>
                    <button class="btn btn-glow btn-add-cart">
                        <i class="ri-shopping-cart-2-line"></i> Add to Cart
                    </button>
                </div>
            </div>
        `;
        grid.appendChild(card);
    });
}

function initListingForm() {
    const form = document.getElementById("form-list-item");
    form.addEventListener("submit", (e) => {
        e.preventDefault();
        
        const title = document.getElementById("list-title").value;
        const price = parseFloat(document.getElementById("list-price").value);
        const type = document.getElementById("list-type").value;
        const description = document.getElementById("list-description").value;
        const imageUrl = document.getElementById("list-image").value;
        
        const newId = state.listings.length + 1;
        const mockSellerAddress = "0x5336E1e04A1d5F69b86e057b7D05621cBcc645b0"; // Default deployer/merchant
        
        const newListing = {
            id: newId,
            seller: mockSellerAddress,
            title: title,
            description: description,
            priceUSD: price,
            imageUrl: imageUrl || null,
            type: type,
            active: true
        };
        
        state.listings.push(newListing);
        
        // Refresh grid
        renderMarketplaceListings();
        
        // Reset form
        form.reset();
        showBannerNotification(`Listing on-chain success! Created item #${newId}: ${title}`);
    });
}

// ================= REVIEWS & FLARITY STARS LOGIC =================

function initReviewsSystem() {
    const sellerSelector = document.getElementById("select-seller");
    sellerSelector.addEventListener("change", (e) => {
        state.selectedReviewSeller = e.target.value;
        renderReviews();
    });

    // Rating star clicks
    const starsContainer = document.getElementById("rating-stars-interactive");
    starsContainer.addEventListener("click", (e) => {
        const star = e.target.closest(".star-interactive");
        if (!star) return;
        
        const rating = parseInt(star.getAttribute("data-val"));
        state.interactiveRating = rating;
        
        // Highlight active stars
        const stars = starsContainer.querySelectorAll(".star-interactive");
        stars.forEach(s => {
            const val = parseInt(s.getAttribute("data-val"));
            if (val <= rating) {
                s.innerHTML = `<i class="ri-star-fill"></i>`;
            } else {
                s.innerHTML = `<i class="ri-star-line"></i>`;
            }
        });
        
        document.getElementById("selected-stars-text").textContent = `${rating} Flarity Stars`;
    });

    // Submit review form
    const form = document.getElementById("form-submit-review");
    form.addEventListener("submit", (e) => {
        e.preventDefault();
        
        const comment = document.getElementById("review-comment").value;
        const seller = state.selectedReviewSeller;
        
        // Verified purchase check
        const relationKey = `shopperAddress_${seller}`;
        if (!state.verifiedPurchases[relationKey]) {
            showBannerNotification("Access Denied: Only verified buyers can submit comments for this seller.");
            return;
        }

        if (!state.reviews[seller]) {
            state.reviews[seller] = [];
        }

        state.reviews[seller].unshift({
            buyer: "0xShopperAddress...",
            rating: state.interactiveRating,
            comment: comment,
            timestamp: "just now"
        });

        renderReviews();
        form.reset();
        
        // Reset interactive stars
        state.interactiveRating = 5;
        const stars = starsContainer.querySelectorAll(".star-interactive");
        stars.forEach(s => s.innerHTML = `<i class="ri-star-fill"></i>`);
        document.getElementById("selected-stars-text").textContent = "5 Flarity Stars";
        
        // Recalculate listing averages
        renderMarketplaceListings();

        showBannerNotification("Review submitted successfully on-chain!");
    });
}

function renderReviews() {
    const list = document.getElementById("reviews-comments-list");
    const avgVal = document.getElementById("average-stars-val");
    const avgVisual = document.getElementById("average-stars-visual");
    const countLabel = document.getElementById("reviews-count-label");
    
    list.innerHTML = "";
    
    const seller = state.selectedReviewSeller;
    const sellerReviews = state.reviews[seller] || [];
    const count = sellerReviews.length;
    
    let sum = 0;
    
    if (count === 0) {
        avgVal.textContent = "0.0";
        avgVisual.innerHTML = `<i class="ri-star-line"></i><i class="ri-star-line"></i><i class="ri-star-line"></i><i class="ri-star-line"></i><i class="ri-star-line"></i>`;
        countLabel.textContent = "No verified purchases reviews yet.";
        list.innerHTML = `<div class="empty-reviews-state">No feedback registered for this seller profile yet.</div>`;
        return;
    }

    sellerReviews.forEach(r => {
        sum += r.rating;
        const commentRow = document.createElement("div");
        commentRow.className = "review-comment-card glass-panel";
        
        let starsRow = "";
        for (let i = 1; i <= 5; i++) {
            if (i <= r.rating) {
                starsRow += `<i class="ri-star-fill text-orange"></i>`;
            } else {
                starsRow += `<i class="ri-star-line"></i>`;
            }
        }

        commentRow.innerHTML = `
            <div class="review-comment-header">
                <span class="reviewer-addr"><i class="ri-user-line"></i> ${r.buyer}</span>
                <span class="review-time">${r.timestamp}</span>
            </div>
            <div class="review-rating-stars-row">${starsRow}</div>
            <p class="review-text">"${r.comment}"</p>
        `;
        list.appendChild(commentRow);
    });

    const average = sum / count;
    avgVal.textContent = average.toFixed(1);
    
    // Average visual stars
    let averageStarsHTML = "";
    for (let i = 1; i <= 5; i++) {
        if (i <= Math.round(average)) {
            averageStarsHTML += `<i class="ri-star-fill text-orange"></i>`;
        } else {
            averageStarsHTML += `<i class="ri-star-line"></i>`;
        }
    }
    avgVisual.innerHTML = averageStarsHTML;
    countLabel.textContent = `Based on ${count} verified ${count === 1 ? 'purchase' : 'purchases'}`;
}

// ================= CHECKOUT MODAL LOGIC =================

function openCheckoutModal() {
    const modal = document.getElementById("checkout-modal");
    
    const totalUSD = state.cart.reduce((sum, item) => sum + (item.price * item.qty), 0);
    const itemList = state.cart.map(item => `${item.name} (x${item.qty})`).join(", ");
    
    const randomHex = Array.from({length: 60}, () => Math.floor(Math.random()*16).toString(16)).join("");
    const payRef = "0x0102" + randomHex;
    
    // Track target seller for this checkout. For a multi-item cart, we choose the seller of the first item
    const targetSeller = state.cart.length > 0 ? state.cart[0].seller : "0x5336E1e04A1d5F69b86e057b7D05621cBcc645b0";

    state.activeInvoice = {
        usdTotal: totalUSD,
        items: itemList,
        payRef: payRef,
        seller: targetSeller,
        currency: "XRP" 
    };
    
    document.getElementById("modal-item-list").textContent = itemList;
    document.getElementById("modal-usd-total").textContent = `$${totalUSD.toFixed(2)}`;
    document.getElementById("payment-reference-hex").textContent = payRef;
    
    const currencyCards = document.querySelectorAll(".asset-selector-card");
    currencyCards.forEach(c => {
        c.classList.remove("active");
        if (c.getAttribute("data-currency") === "XRP") {
            c.classList.add("active");
        }
    });

    updateModalCalculations();
    
    modal.classList.add("active");
}

function closeCheckoutModal() {
    document.getElementById("checkout-modal").classList.remove("active");
}

function updateModalCalculations() {
    if (!state.activeInvoice) return;
    
    const currency = state.activeInvoice.currency;
    const usdTotal = state.activeInvoice.usdTotal;
    const cryptoPrice = state.prices[currency];
    
    document.getElementById("rate-XRP").textContent = `1 XRP = $${state.prices.XRP.toFixed(4)}`;
    document.getElementById("rate-BTC").textContent = `1 BTC = $${state.prices.BTC.toLocaleString(undefined, {maximumFractionDigits:0})}`;
    document.getElementById("rate-DOGE").textContent = `1 DOGE = $${state.prices.DOGE.toFixed(4)}`;
    
    const cryptoSubtotal = usdTotal / cryptoPrice;
    const mintFee = cryptoSubtotal * 0.001; 
    const cryptoTotal = cryptoSubtotal + mintFee;
    
    document.getElementById("modal-mint-fee").textContent = `${mintFee.toFixed(currency === 'BTC' ? 6 : 4)} ${currency}`;
    document.getElementById("modal-crypto-total").textContent = `${cryptoTotal.toFixed(currency === 'BTC' ? 6 : 4)} ${currency}`;
    
    const destAddr = DESTINATION_ADDRESSES[currency];
    document.getElementById("merchant-destination-address").textContent = destAddr;
    
    state.activeInvoice.cryptoTotal = cryptoTotal;
    state.activeInvoice.destAddr = destAddr;
}

function routeToWalletPayment() {
    if (!state.activeInvoice) return;
    
    const invoice = state.activeInvoice;
    
    document.getElementById("wallet-dest-addr").textContent = invoice.destAddr;
    document.getElementById("wallet-pay-ref").textContent = invoice.payRef;
    
    let decimals = invoice.currency === 'BTC' ? 6 : 4;
    document.getElementById("wallet-amount-due").textContent = `${invoice.cryptoTotal.toFixed(decimals)} ${invoice.currency}`;
    
    const walletAssetCards = document.querySelectorAll(".wallet-asset-pill");
    walletAssetCards.forEach(card => {
        card.classList.remove("active");
        if (card.getAttribute("data-asset") === invoice.currency) {
            card.classList.add("active");
        }
    });
    
    const broadcastBtn = document.getElementById("btn-broadcast-tx");
    broadcastBtn.disabled = false;
    
    closeCheckoutModal();
    
    const visualizerTabBtn = document.getElementById("nav-visualizer-btn");
    visualizerTabBtn.click();
    
    const badge = document.getElementById("pending-tx-badge");
    badge.style.display = "inline-block";
    
    showBannerNotification("Checkout details loaded to shopper wallet terminal. Ready to broadcast cross-chain payment.");
}

function copyText(elementId) {
    const text = document.getElementById(elementId).textContent;
    navigator.clipboard.writeText(text).then(() => {
        showBannerNotification("Copied to clipboard!");
    });
}

// ================= WALLET & PROTOCOL VISUALIZER =================

function initVisualizer() {
    const broadcastBtn = document.getElementById("btn-broadcast-tx");
    broadcastBtn.addEventListener("click", runFDCAttestationSimulation);
    
    const assetCards = document.querySelectorAll(".wallet-asset-pill");
    assetCards.forEach(card => {
        card.addEventListener("click", () => {
            assetCards.forEach(c => c.classList.remove("active"));
            card.classList.add("active");
            
            if (!state.activeInvoice) {
                const asset = card.getAttribute("data-asset");
                document.getElementById("wallet-dest-addr").textContent = "No active invoice";
                document.getElementById("wallet-pay-ref").textContent = "0x0000000000...";
                document.getElementById("wallet-amount-due").textContent = `0.00 ${asset}`;
                broadcastBtn.disabled = true;
            }
        });
    });
}

async function runFDCAttestationSimulation() {
    const broadcastBtn = document.getElementById("btn-broadcast-tx");
    broadcastBtn.disabled = true;
    
    const badge = document.getElementById("pending-tx-badge");
    badge.style.display = "none";
    
    if (!state.activeInvoice) return;
    
    const invoice = state.activeInvoice;
    const currency = invoice.currency;
    const totalPaid = invoice.cryptoTotal;
    const seller = invoice.seller;
    
    const txHash = "0x" + Array.from({length: 64}, () => Math.floor(Math.random()*16).toString(16)).join("");
    
    // Reset FDC visualizer steps UI
    const stepIds = ["step-broadcast", "step-voting", "step-merkle", "step-mint"];
    stepIds.forEach(id => {
        const s = document.getElementById(id);
        s.classList.remove("active", "completed");
    });
    
    const validatorNodes = document.querySelectorAll(".validator-node");
    validatorNodes.forEach(v => v.classList.remove("voted"));
    
    document.getElementById("merkle-root").textContent = "Root: 0x00...";
    document.getElementById("merkle-root").classList.remove("matched");
    document.getElementById("merkle-left").classList.remove("active");
    document.getElementById("merkle-right").classList.remove("active");
    
    // --- STAGE 1: TRANSACTION DETECTED ---
    const step1 = document.getElementById("step-broadcast");
    step1.classList.add("active");
    document.getElementById("fdc-data-request").innerHTML = `
        <strong>External Tx Hash:</strong> <span class="text-orange">${txHash.substring(0, 18)}...</span><br>
        <strong>Network:</strong> ${currency === 'XRP' ? 'XRPL' : currency === 'BTC' ? 'Bitcoin' : 'Dogecoin'}<br>
        <strong>Reference:</strong> ${invoice.payRef.substring(0, 14)}...
    `;
    
    state.balances.wallet[currency] -= totalPaid;
    updateWalletBalancesUI();
    
    await sleep(2500);
    step1.classList.remove("active");
    step1.classList.add("completed");
    
    // --- STAGE 2: BITVOTING ---
    const step2 = document.getElementById("step-voting");
    step2.classList.add("active");
    
    for (let i = 1; i <= 10; i++) {
        await sleep(200);
        const node = document.querySelector(`.validator-node[data-id="${i}"]`);
        if (node) node.classList.add("voted");
    }
    
    await sleep(1500);
    step2.classList.remove("active");
    step2.classList.add("completed");
    
    // --- STAGE 3: MERKLE TREE CONSTRUCTION ---
    const step3 = document.getElementById("step-merkle");
    step3.classList.add("active");
    
    const mRoot = "0x" + Array.from({length: 40}, () => Math.floor(Math.random()*16).toString(16)).join("");
    
    await sleep(500);
    document.getElementById("merkle-right").classList.add("active");
    document.getElementById("merkle-right").textContent = `H(${invoice.payRef.substring(2, 6)})`;
    await sleep(500);
    document.getElementById("merkle-left").classList.add("active");
    
    await sleep(800);
    const rootEl = document.getElementById("merkle-root");
    rootEl.classList.add("matched");
    rootEl.textContent = `Root: ${mRoot.substring(0, 10)}...`;
    
    await sleep(1500);
    step3.classList.remove("active");
    step3.classList.add("completed");
    
    // --- STAGE 4: ROOT SUBMISSION & MINTING ---
    const step4 = document.getElementById("step-mint");
    step4.classList.add("active");
    
    const mintTx = "0x" + Array.from({length: 64}, () => Math.floor(Math.random()*16).toString(16)).join("");
    const fassetAmount = totalPaid * 0.999; 
    
    document.getElementById("fdc-data-proof").innerHTML = `
        <strong>On-Chain Merkle Root verified!</strong><br>
        <strong>Seller Target Wallet:</strong> <span class="text-orange">${seller.substring(0, 10)}...${seller.substring(38)}</span><br>
        <strong>Minted FAsset:</strong> <span class="text-green">+${fassetAmount.toFixed(4)} F${currency}</span> (Settle Payout)<br>
        <strong>Flare Verification Tx:</strong> <span class="text-orange">${mintTx.substring(0, 18)}...</span>
    `;
    
    await sleep(2000);
    step4.classList.remove("active");
    step4.classList.add("completed");
    
    // --- PROCESS TRANSACTION SUCCESS ---
    // Update merchant balances if the merchant is the admin
    if (seller === "0x5336E1e04A1d5F69b86e057b7D05621cBcc645b0") {
        const mintedType = `F${currency}`; 
        state.balances.merchant[mintedType] += fassetAmount;
        state.balances.merchant.revenue += usdTotalConversion(currency, totalPaid);
        updateMerchantDashboardUI();
    }
    
    // Pre-credit purchase verification so the buyer can leave reviews for this seller
    const relationKey = `shopperAddress_${seller}`;
    state.verifiedPurchases[relationKey] = true;

    // Add to ledger
    const orderId = "#" + Math.floor(Math.random() * 1000 + 8025);
    const timeText = "just now";
    
    let chainClass = "xrp-color";
    let chainName = "XRPL";
    if (currency === 'BTC') {
        chainClass = "btc-color";
        chainName = "Bitcoin";
    } else if (currency === 'DOGE') {
        chainClass = "doge-color";
        chainName = "Dogecoin";
    }
    
    state.ledger.unshift({
        id: orderId,
        cryptoPaid: `${totalPaid.toFixed(currency==='BTC'?5:2)} ${currency}`,
        fassetsMinted: `${fassetAmount.toFixed(currency==='BTC'?5:2)} F${currency}`,
        chain: chainName,
        chainClass: chainClass,
        status: "Verified",
        time: timeText
    });
    
    renderLedger();
    clearCart();
    
    state.activeInvoice = null;
    
    showBannerNotification(`FAssets successfully verified & minted to seller ${seller.substring(0, 6)}...!`);
}

function updateWalletBalancesUI() {
    document.getElementById("wallet-bal-xrp").textContent = `${state.balances.wallet.XRP.toFixed(2)} XRP`;
    document.getElementById("wallet-bal-btc").textContent = `${state.balances.wallet.BTC.toFixed(4)} BTC`;
    document.getElementById("wallet-bal-doge").textContent = `${state.balances.wallet.DOGE.toFixed(2)} DOGE`;
}

function usdTotalConversion(currency, cryptoAmount) {
    return cryptoAmount * state.prices[currency];
}

function sleep(ms) {
    return new Promise(resolve => setTimeout(resolve, ms));
}

// ================= MERCHANT DASHBOARD LOGIC =================

function initWrapping() {
    const wrapBtn = document.getElementById("btn-wrap-action");
    wrapBtn.addEventListener("click", () => {
        const wrapAmountInput = document.getElementById("wrap-amount");
        const amount = parseFloat(wrapAmountInput.value);
        const type = document.getElementById("wrap-type").value;
        
        if (isNaN(amount) || amount <= 0) {
            showBannerNotification("Please enter a valid amount to wrap/unwrap.");
            return;
        }
        
        if (type === "wrap") {
            if (state.balances.merchant.FLR < amount) {
                showBannerNotification("Insufficient FLR balance.");
                return;
            }
            state.balances.merchant.FLR -= amount;
            state.balances.merchant.WFLR += amount;
            showBannerNotification(`Wrapped ${amount.toFixed(2)} FLR into WFLR.`);
        } else {
            if (state.balances.merchant.WFLR < amount) {
                showBannerNotification("Insufficient WFLR balance.");
                return;
            }
            state.balances.merchant.WFLR -= amount;
            state.balances.merchant.FLR += amount;
            showBannerNotification(`Unwrapped ${amount.toFixed(2)} WFLR into FLR.`);
        }
        
        wrapAmountInput.value = "";
        updateMerchantDashboardUI();
    });
    
    document.getElementById("btn-refresh-ledger").addEventListener("click", () => {
        renderLedger();
        showBannerNotification("Ledger up to date.");
    });
}

function updateMerchantDashboardUI() {
    document.getElementById("merchant-revenue").textContent = `$${state.balances.merchant.revenue.toLocaleString(undefined, {minimumFractionDigits: 2, maximumFractionDigits: 2})}`;
    
    document.getElementById("bal-fxrp").textContent = state.balances.merchant.FXRP.toLocaleString(undefined, {maximumFractionDigits: 2});
    document.getElementById("bal-fbtc").textContent = state.balances.merchant.FBTC.toFixed(4);
    document.getElementById("bal-fdoge").textContent = state.balances.merchant.FDOGE.toLocaleString(undefined, {maximumFractionDigits: 2});
    
    document.getElementById("merchant-flr-balance").textContent = state.balances.merchant.FLR.toLocaleString(undefined, {minimumFractionDigits: 2});
    document.getElementById("merchant-wflr-balance").textContent = state.balances.merchant.WFLR.toLocaleString(undefined, {minimumFractionDigits: 2});
    
    document.getElementById("delegated-amount").textContent = `${state.balances.merchant.WFLR.toLocaleString(undefined, {maximumFractionDigits: 0})} WFLR`;
}

function renderLedger() {
    const tbody = document.getElementById("ledger-body");
    if (!tbody) return;
    tbody.innerHTML = "";
    
    state.ledger.forEach(item => {
        const tr = document.createElement("tr");
        tr.innerHTML = `
            <td>${item.id}</td>
            <td>${item.cryptoPaid}</td>
            <td>${item.fassetsMinted}</td>
            <td><span class="chain-badge ${item.chainClass}">${item.chain}</span></td>
            <td><span class="status-badge verified"><i class="ri-checkbox-circle-fill"></i> ${item.status}</span></td>
            <td>${item.time}</td>
        `;
        tbody.appendChild(tr);
    });
}

function clearCart() {
    state.cart = [];
    updateCartUI();
    
    document.getElementById("wallet-dest-addr").textContent = "Connect checkout to load...";
    document.getElementById("wallet-pay-ref").textContent = "0x0000000000...";
    document.getElementById("wallet-amount-due").textContent = "0.00";
}

// Simple temporary toast/notification banner
function showBannerNotification(message) {
    const banner = document.createElement("div");
    banner.style.position = "fixed";
    banner.style.bottom = "24px";
    banner.style.left = "50%";
    banner.style.transform = "translateX(-50%) translateY(100px)";
    banner.style.background = "rgba(10, 20, 36, 0.9)";
    banner.style.backdropFilter = "blur(12px)";
    banner.style.border = "1px solid var(--color-flare)";
    banner.style.color = "#fff";
    banner.style.padding = "12px 24px";
    banner.style.borderRadius = "8px";
    banner.style.fontSize = "0.9rem";
    banner.style.fontWeight = "600";
    banner.style.boxShadow = "var(--shadow-main)";
    banner.style.zIndex = "9999";
    banner.style.transition = "transform 0.4s cubic-bezier(0.175, 0.885, 0.32, 1.275)";
    
    banner.innerHTML = `<i class="ri-information-line text-orange" style="margin-right:8px; vertical-align:middle;"></i> ${message}`;
    document.body.appendChild(banner);
    
    setTimeout(() => {
        banner.style.transform = "translateX(-50%) translateY(0)";
    }, 100);
    
    setTimeout(() => {
        banner.style.transform = "translateX(-50%) translateY(100px)";
        setTimeout(() => {
            banner.remove();
        }, 400);
    }, 3500);
}
