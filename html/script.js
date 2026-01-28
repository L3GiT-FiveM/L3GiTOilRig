const RESOURCE_NAME = (typeof GetParentResourceName === "function")
    ? GetParentResourceName()
    : "L3GiTOilRig";

let currentRigId = null;
let currentRigName = "";
let currentModal = null;
let lastRigData = null;
let supplierConfig = { fuelCost: 0, currentFuel: 0, maxHold: 9 };
let supplierBuyBusy = false;
let supplierQty = 1;

let buyerConfig = { barrelPrice: 0, currentBarrels: 0 };
let buyerSellBusy = false;
let buyerQty = 1;

function setDocumentTitle(cfg) {
    const uiTitle = (cfg && typeof cfg.uiTitle === "string") ? cfg.uiTitle.trim() : "";
    const uiKicker = (cfg && typeof cfg.uiKicker === "string") ? cfg.uiKicker.trim() : "";
    const uiSubtitle = (cfg && typeof cfg.uiSubtitle === "string") ? cfg.uiSubtitle.trim() : "";

    const parts = [];
    parts.push(uiTitle || "L3GiTOilRig");

    // Prefer the kicker (short label), else subtitle.
    if (uiKicker) parts.push(uiKicker);
    else if (uiSubtitle) parts.push(uiSubtitle);

    document.title = parts.join(" — ");
}

function setOxInventoryItemImage(imgEl, itemName) {
    if (!imgEl) return;
    const name = (itemName || "").trim();
    if (!name) return;

    const base = `nui://ox_inventory/web/images/${name}`;
    const exts = [".png", ".webp", ".jpg", ".jpeg"];
    let idx = 0;

    const tryNext = () => {
        if (idx >= exts.length) return;
        imgEl.src = `${base}${exts[idx++]}`;
    };

    imgEl.onerror = () => {
        tryNext();
    };

    tryNext();
}
let rigConfig = {
    maxFuel: 9,
    fuelBatch: 3,
    maxBarrels: 10,
    productionTimeLabel: "00:00",
    fuelCost: 0,
    barrelSellPrice: 0,
    fuelToYield: {
        3: { barrels: 1, label: "" },
    },
};

function $(id) {
    return document.getElementById(id);
}

function setText(id, value) {
    const el = $(id);
    if (!el) return;
    if (typeof value !== "string") return;
    el.textContent = value;
}

async function postNui(endpoint, payload) {
    try {
        await fetch(`https://${RESOURCE_NAME}/${endpoint}`, {
            method: "POST",
            headers: { "Content-Type": "application/json; charset=UTF-8" },
            body: JSON.stringify(payload || {}),
        });
    } catch {
        // NUI fetch can throw when focus changes; safe to ignore.
    }
}

function showUI() {
    $("contract-container").classList.remove("hidden");
}

function hideUI() {
    $("contract-container").classList.add("hidden");
}

function showSupplierUI(cfg) {
    supplierConfig = {
        ...supplierConfig,
        ...(cfg || {}),
    };

    setDocumentTitle(cfg);

    if (cfg && typeof cfg.uiKicker === "string") setText("supplier-kicker", cfg.uiKicker);
    if (cfg && typeof cfg.uiTitle === "string") setText("supplier-title", cfg.uiTitle);
    if (cfg && typeof cfg.uiSubtitle === "string") setText("supplier-subtitle", cfg.uiSubtitle);

    supplierQty = 1;

    // Only one panel visible at a time.
    hideUI();

    const price = Number(supplierConfig.fuelCost || 0);
    const priceText = price > 0 ? `$${price}` : "$0";
    const p2 = $("shop-fuel-price");
    if (p2) p2.textContent = priceText;

    setOxInventoryItemImage($("shop-item-img"), "rig_fuel");

    const infoView = $("supplier-info-view");
    const shopView = $("supplier-shop-view");
    if (infoView) infoView.classList.remove("hidden");
    if (shopView) shopView.classList.add("hidden");

    updateSupplierShopTotals();

    $("supplier-container").classList.remove("hidden");
}

function hideSupplierUI() {
    const el = $("supplier-container");
    if (el) el.classList.add("hidden");
}

function showBuyerUI(cfg) {
    buyerConfig = {
        ...buyerConfig,
        ...(cfg || {}),
    };

    setDocumentTitle(cfg);

    if (cfg && typeof cfg.uiKicker === "string") setText("buyer-kicker", cfg.uiKicker);
    if (cfg && typeof cfg.uiTitle === "string") setText("buyer-title", cfg.uiTitle);
    if (cfg && typeof cfg.uiSubtitle === "string") setText("buyer-subtitle", cfg.uiSubtitle);

    // Close other panels.
    hideUI();
    hideSupplierUI();

    const unit = Number(buyerConfig.barrelPrice || 0);
    const unitText = unit > 0 ? `$${unit}` : "$0";
    const unitEl = $("buyer-unit-price");
    if (unitEl) unitEl.textContent = unitText;

    setOxInventoryItemImage($("buyer-item-img"), "oil_barrel");

    buyerQty = 1;
    updateBuyerTotals();

    const el = $("buyer-container");
    if (el) el.classList.remove("hidden");
}

function hideBuyerUI() {
    const el = $("buyer-container");
    if (el) el.classList.add("hidden");
}

function updateBuyerTotals() {
    const barrels = Math.max(0, Number(buyerConfig.currentBarrels || 0));
    const unit = Math.max(0, Number(buyerConfig.barrelPrice || 0));

    const maxQty = barrels;
    if (maxQty <= 0) {
        buyerQty = 0;
        const qtyEl = $("buyer-qty-value");
        if (qtyEl) qtyEl.textContent = "0";
        const totalEl = $("buyer-total-price");
        if (totalEl) totalEl.textContent = "$0";

        const sellBtn = $("btn-buyer-sell");
        if (sellBtn) {
            sellBtn.disabled = true;
            sellBtn.textContent = "No Barrels";
        }

        const minus = $("btn-buyer-qty-minus");
        const plus = $("btn-buyer-qty-plus");
        if (minus) minus.disabled = true;
        if (plus) plus.disabled = true;
        return;
    }

    buyerQty = Math.max(1, Math.min(maxQty, Number(buyerQty) || 1));

    const qtyEl = $("buyer-qty-value");
    if (qtyEl) qtyEl.textContent = String(buyerQty);

    const total = unit * buyerQty;
    const totalEl = $("buyer-total-price");
    if (totalEl) totalEl.textContent = total > 0 ? `$${total}` : "$0";

    const sellBtn = $("btn-buyer-sell");
    if (sellBtn) {
        sellBtn.disabled = false;
        sellBtn.textContent = "Purchase";
    }

    const minus = $("btn-buyer-qty-minus");
    const plus = $("btn-buyer-qty-plus");
    if (minus) minus.disabled = buyerQty <= 1;
    if (plus) plus.disabled = buyerQty >= maxQty;
}

function supplierOpenShop() {
    const infoView = $("supplier-info-view");
    const shopView = $("supplier-shop-view");
    if (infoView) infoView.classList.add("hidden");
    if (shopView) shopView.classList.remove("hidden");

    // Refresh inventory-driven limits when entering shop.
    postNui("requestSupplierRefresh", {});
    updateSupplierShopTotals();
}

function supplierBackToInfo() {
    const infoView = $("supplier-info-view");
    const shopView = $("supplier-shop-view");
    if (shopView) shopView.classList.add("hidden");
    if (infoView) infoView.classList.remove("hidden");
}

function updateSupplierShopTotals() {
    const currentFuel = Number(supplierConfig.currentFuel || 0);
    const maxHold = Number(supplierConfig.maxHold || 9);

    const maxQty = Math.max(0, maxHold - currentFuel);
    if (maxQty <= 0) {
        supplierQty = 0;

        const qtyEl = $("supplier-qty-value");
        if (qtyEl) qtyEl.textContent = "0";

        const totalEl = $("supplier-total-price");
        if (totalEl) totalEl.textContent = "$0";

        const minus = $("btn-supplier-qty-minus");
        const plus = $("btn-supplier-qty-plus");
        if (minus) minus.disabled = true;
        if (plus) plus.disabled = true;

        const buyBtn = $("btn-shop-buy");
        if (buyBtn) {
            buyBtn.disabled = true;
            buyBtn.textContent = `Inventory Full (${maxHold}/${maxHold})`;
        }
        return;
    }

    supplierQty = Math.max(1, Math.min(maxQty, Number(supplierQty) || 1));

    const qtyEl = $("supplier-qty-value");
    if (qtyEl) qtyEl.textContent = String(supplierQty);

    const unit = Math.max(0, Number(supplierConfig.fuelCost || 0));
    const total = unit * supplierQty;
    const totalEl = $("supplier-total-price");
    if (totalEl) totalEl.textContent = total > 0 ? `$${total}` : "$0";

    const buyBtn = $("btn-shop-buy");
    if (!buyBtn) return;

    buyBtn.disabled = false;
    buyBtn.textContent = "Purchase";

    const minus = $("btn-supplier-qty-minus");
    const plus = $("btn-supplier-qty-plus");
    if (minus) minus.disabled = supplierQty <= 1;
    if (plus) plus.disabled = supplierQty >= maxQty;
}

function setRigNameUI(name) {
    currentRigName = typeof name === "string" ? name : "";
    const display = $("rig-name-display");
    if (display) display.textContent = currentRigName && currentRigName.trim() ? currentRigName : "(not set)";
}

function openNamePopup() {
    const popup = $("name-popup");
    const input = $("name-popup-input");
    if (!popup || !input) return;
    input.value = currentRigName || "";
    popup.classList.remove("hidden");
    input.focus();
    input.select();
}

function closeNamePopup() {
    const popup = $("name-popup");
    if (!popup) return;
    popup.classList.add("hidden");
}

function openModal(payload) {
    currentModal = payload;
    $("modal-title").textContent = payload.title || "Confirmation";
    $("modal-message").textContent = payload.message || "";

    $("modal-confirm-label").textContent = payload.confirmLabel || "Confirm";
    $("modal-cancel-label").textContent = payload.cancelLabel || "Cancel";

    $("modal").classList.remove("hidden");
}

function closeModal() {
    $("modal").classList.add("hidden");
    currentModal = null;
}

function createNotification({ title, message, type = "info", duration = 4000 }) {
    const container = $("miningNotifications") || document.body;
    const note = document.createElement("div");

    note.classList.add("miningNotify");
    note.classList.add(type || "info");

    const safeTitle = (title || "").trim();
    const safeMessage = (message || "").trim();
    note.innerText = safeTitle ? `${safeTitle}: ${safeMessage}` : safeMessage;

    container.appendChild(note);

    window.setTimeout(() => {
        note.remove();
    }, Number(duration) || 4000);
}

function setBarPct(el, pct) {
    if (!el) return;
    const p = Math.max(0, Math.min(1, Number(pct) || 0));
    el.style.width = `${p * 100}%`;
}

function setVerticalProgress(pct) {
    // Legacy name: the UI now uses a horizontal bar to match the storage meter.
    const p = Math.max(0, Math.min(1, Number(pct) || 0));
    const fill = $("progress-fill");
    const marker = $("progress-marker");
    if (fill) fill.style.width = `${p * 100}%`;
    if (marker) marker.style.left = `${p * 100}%`;
}

function setBtnVariant(btn, makePrimary) {
    if (!btn) return;
    btn.classList.toggle('primary', !!makePrimary);
    btn.classList.toggle('secondary', !makePrimary);
}

function updateRigPanel(payload) {
    const { rigId, data } = payload;
    currentRigId = rigId;
    lastRigData = data;

    const maxBarrels = Number(data.maxBarrels || rigConfig.maxBarrels || 10);
    const barrelsReady = Number(data.barrelsReady || 0);

    // Rig ID / badge removed from UI (internal rigId still used for logic).
    $("rig-fuel").textContent = `${Number(data.fuelCans || 0)} / ${Number(data.maxFuel || rigConfig.maxFuel || 0)}`;
    $("rig-barrels").textContent = String(barrelsReady);

    const badgeStatus = $("rig-status");
    const statusRaw = (data.status || "OUT_OF_FUEL").toUpperCase();
    const isRunning = statusRaw === "ACTIVE" || statusRaw === "RUNNING";
    const isReady = statusRaw === "READY";
    const isOutOfFuel = !isRunning && !isReady;
    badgeStatus.textContent = isRunning ? "Running" : (isReady ? "Ready" : "Out of fuel");
    badgeStatus.classList.toggle("active", isRunning);
    badgeStatus.classList.toggle("ready", isReady);
    badgeStatus.classList.toggle("danger", isOutOfFuel);
    badgeStatus.classList.toggle("idle", !isRunning);

    // Keep countdown only. If active: show remaining. If idle: show N/A.
    $("rig-time").textContent = isRunning ? (data.timeRemaining || "00:00") : "N/A";

    // Storage bar + label
    const storagePct = Number(data.storagePct ?? (maxBarrels > 0 ? (barrelsReady / maxBarrels) : 0));
    setBarPct($("storage-fill"), storagePct);
    const storageText = $("storage-text");
    if (storageText) storageText.textContent = `${barrelsReady} / ${maxBarrels}`;

    // Vertical cycle progress (marker moves down as progress increases)
    setVerticalProgress(Number(data.progressPct || 0));

    // Disable buttons when appropriate.
    const maxFuel = Number(data.maxFuel || rigConfig.maxFuel || 9);
    const batch = Number(data.fuelBatch || rigConfig.fuelBatch || 3);
    const fuelNow = Number(data.fuelCans || 0);
    const playerFuel = Number(data.playerFuel || 0);

    const fuelBtn = $("btn-fuel");
    if (fuelBtn) {
        const canAddFuel = fuelNow < maxFuel && playerFuel > 0;
        // While fueling popup is active, we force-disable the button; otherwise use normal logic.
        fuelBtn.disabled = fuelingBusy ? true : !canAddFuel;
        // When player has fuel, it should look like the "action" button.
        setBtnVariant(fuelBtn, canAddFuel);
    }

    const startBtn = $("btn-start");
    if (startBtn) {
        const canStart = !isRunning && fuelNow >= batch;
        startBtn.disabled = !canStart;
        // When start is possible (enough rig fuel), make it match the Add Fuel primary style.
        setBtnVariant(startBtn, canStart);
    }
    $("btn-collect").disabled = Number(data.barrelsReady || 0) <= 0;
}

let fuelingAnim = null;
let fuelingBusy = false;
let fuelingHideTimer = null;
function setFuelingPopup(visible, text) {
    const popup = $("fueling-popup");
    if (!popup) return;
    if (visible) popup.classList.remove("hidden");
    else popup.classList.add("hidden");
    const t = $("fueling-text");
    if (t && typeof text === "string") t.textContent = text;
}

function refreshFuelButtonFromState() {
    const fuelBtn = $("btn-fuel");
    if (!fuelBtn) return;
    if (fuelingBusy) {
        fuelBtn.disabled = true;
        return;
    }

    const data = lastRigData || {};
    const maxFuel = Number(data.maxFuel || rigConfig.maxFuel || 9);
    const fuelNow = Number(data.fuelCans || 0);
    const playerFuel = Number(data.playerFuel || 0);
    const canAddFuel = fuelNow < maxFuel && playerFuel > 0;
    fuelBtn.disabled = !canAddFuel;
}

function startFuelingAnimation(durationMs) {
    const bar = $("fueling-bar");
    if (!bar) return;

    if (fuelingAnim) {
        cancelAnimationFrame(fuelingAnim);
        fuelingAnim = null;
    }

    const start = performance.now();
    const dur = Math.max(250, Number(durationMs) || 4000);
    bar.style.width = "0%";

    const tick = (now) => {
        const pct = Math.max(0, Math.min(1, (now - start) / dur));
        bar.style.width = `${pct * 100}%`;
        if (pct < 1) fuelingAnim = requestAnimationFrame(tick);
    };
    fuelingAnim = requestAnimationFrame(tick);
}

window.addEventListener("message", (event) => {
    const msg = event.data;
    if (!msg || !msg.action) return;

    switch (msg.action) {
        case "showSupplierUI":
            showSupplierUI(msg.config || {});
            break;
        case "hideSupplierUI":
            hideSupplierUI();
            break;
        case "showBuyerUI":
            showBuyerUI(msg.config || {});
            break;
        case "updateSupplierUI":
            supplierConfig = { ...supplierConfig, ...(msg.config || {}) };
            updateSupplierShopTotals();
            break;
        case "updateBuyerUI":
            buyerConfig = { ...buyerConfig, ...(msg.config || {}) };
            updateBuyerTotals();
            break;
        case "hideBuyerUI":
            hideBuyerUI();
            break;
        case "showRigUI": {
            if (msg.rigId) currentRigId = msg.rigId;
            if (msg.config) {
                rigConfig = {
                    ...rigConfig,
                    ...msg.config,
                    fuelToYield: msg.config.fuelToYield || rigConfig.fuelToYield,
                };

                setDocumentTitle(rigConfig);

                if (rigConfig.subtitle) setText("ui-subtitle", rigConfig.subtitle);
                if (rigConfig.uiKicker) setText("ui-kicker", rigConfig.uiKicker);
                if (rigConfig.uiTitle) setText("ui-title", rigConfig.uiTitle);
                if (rigConfig.uiSubtitle) setText("ui-subtitle", rigConfig.uiSubtitle);
                if (rigConfig.infoNote) setText("rig-info-text", rigConfig.infoNote);
            }

            if (typeof msg.rigName === "string") {
                setRigNameUI(msg.rigName);
            }
            showUI();
            postNui("uiShown", { rigId: currentRigId });
            break;
        }
        case "hideRigUI":
            hideUI();
            break;
        case "updateRigPanel":
            updateRigPanel(msg);
            break;
        case "setRigName": {
            if (msg.rigId && currentRigId && msg.rigId !== currentRigId) break;
            if (typeof msg.rigName === "string") setRigNameUI(msg.rigName);
            break;
        }
        case "openModal":
            openModal(msg);
            break;
        case "notify":
            createNotification({
                title: msg.title,
                message: msg.message,
                type: msg.nType || msg.type || "info",
                duration: msg.duration,
            });
            break;
        case "fueling":
            if (msg.state === "start") {
                    fuelingBusy = true;
                    const fuelBtn = $("btn-fuel");
                    if (fuelBtn) fuelBtn.disabled = true;

                if (fuelingHideTimer) {
                    clearTimeout(fuelingHideTimer);
                    fuelingHideTimer = null;
                }

                setFuelingPopup(true, "Fueling rig...");
                startFuelingAnimation(msg.duration || 4000);
            } else if (msg.state === "cancel") {
                setFuelingPopup(true, "Fueling canceled.");
                    fuelingBusy = false;

                if (fuelingHideTimer) clearTimeout(fuelingHideTimer);
                fuelingHideTimer = window.setTimeout(() => {
                    setFuelingPopup(false);
                    fuelingHideTimer = null;
                    refreshFuelButtonFromState();
                }, 650);
            } else if (msg.state === "done") {
                setFuelingPopup(true, "Fueling complete.");
                    fuelingBusy = false;

                if (fuelingHideTimer) clearTimeout(fuelingHideTimer);
                fuelingHideTimer = window.setTimeout(() => {
                    setFuelingPopup(false);
                    fuelingHideTimer = null;
                    refreshFuelButtonFromState();
                }, 650);
            }
            break;
        default:
            break;
    }
});

window.addEventListener("DOMContentLoaded", () => {
    // Let Lua know NUI loaded successfully.
    postNui("uiReady", {});

    setOxInventoryItemImage($("gauge-barrel-img"), "oil_barrel");

    $("btn-close").addEventListener("click", () => postNui("closeUI", {}));

    const supplierClose = $("btn-supplier-close");
    if (supplierClose) supplierClose.addEventListener("click", () => postNui("closeSupplierUI", {}));

    const buyerClose = $("btn-buyer-close");
    if (buyerClose) buyerClose.addEventListener("click", () => postNui("closeBuyerUI", {}));

    const supplierShop = $("btn-supplier-shop");
    if (supplierShop) supplierShop.addEventListener("click", supplierOpenShop);

    const shopBack = $("btn-shop-back");
    if (shopBack) shopBack.addEventListener("click", supplierBackToInfo);

    const shopBuy = $("btn-shop-buy");
    if (shopBuy) {
        shopBuy.addEventListener("click", () => {
            if (supplierBuyBusy) return;
            if (supplierQty <= 0) return;
            supplierBuyBusy = true;
            shopBuy.disabled = true;
            postNui("buyDiesel", { amount: supplierQty });
            window.setTimeout(() => {
                supplierBuyBusy = false;
                // Re-evaluate based on latest UI state.
                updateSupplierShopTotals();
            }, 700);
        });
    }

    const supplierMinus = $("btn-supplier-qty-minus");
    if (supplierMinus) supplierMinus.addEventListener("click", () => {
        supplierQty = Math.max(1, supplierQty - 1);
        updateSupplierShopTotals();
    });

    const supplierPlus = $("btn-supplier-qty-plus");
    if (supplierPlus) supplierPlus.addEventListener("click", () => {
        const currentFuel = Math.max(0, Number(supplierConfig.currentFuel || 0));
        const maxHold = Math.max(0, Number(supplierConfig.maxHold || 9));
        const maxQty = Math.max(0, maxHold - currentFuel);
        supplierQty = Math.min(maxQty, supplierQty + 1);
        updateSupplierShopTotals();
    });

    const buyerSell = $("btn-buyer-sell");
    if (buyerSell) {
        buyerSell.addEventListener("click", () => {
            if (buyerSellBusy) return;
            if (buyerQty <= 0) return;
            buyerSellBusy = true;
            buyerSell.disabled = true;
            postNui("sellBarrels", { amount: buyerQty });
            window.setTimeout(() => {
                buyerSellBusy = false;
                updateBuyerTotals();
            }, 700);
        });
    }

    const buyerMinus = $("btn-buyer-qty-minus");
    if (buyerMinus) buyerMinus.addEventListener("click", () => {
        buyerQty = Math.max(1, buyerQty - 1);
        updateBuyerTotals();
    });

    const buyerPlus = $("btn-buyer-qty-plus");
    if (buyerPlus) buyerPlus.addEventListener("click", () => {
        const maxQty = Math.max(0, Number(buyerConfig.currentBarrels || 0));
        buyerQty = Math.min(maxQty, buyerQty + 1);
        updateBuyerTotals();
    });

    $("btn-fuel").addEventListener("click", () => {
        if (!currentRigId) return;
            if (fuelingBusy) return;
        postNui("fuelRig", { rigId: currentRigId, cans: 1 });
    });

    const startBtn = $("btn-start");
    if (startBtn) {
        startBtn.addEventListener("click", () => {
            if (!currentRigId) return;
            postNui("startCycle", { rigId: currentRigId });
        });
    }

    $("btn-collect").addEventListener("click", () => {
        if (!currentRigId) return;
        postNui("collectBarrel", { rigId: currentRigId });
    });

    const setNameBtn = $("btn-set-name");
    if (setNameBtn) {
        setNameBtn.addEventListener("click", () => {
            if (!currentRigId) return;
            openNamePopup();
        });
    }

    const nameCancel = $("name-popup-cancel");
    const nameSave = $("name-popup-save");
    const nameInput = $("name-popup-input");
    const nameBackdrop = $("name-popup")?.querySelector?.(".popup-backdrop");

    if (nameCancel) nameCancel.addEventListener("click", closeNamePopup);
    if (nameBackdrop) nameBackdrop.addEventListener("click", closeNamePopup);

    const doSaveName = () => {
        if (!currentRigId) return;
        postNui("setRigName", { rigId: currentRigId, rigName: (nameInput && nameInput.value) ? nameInput.value : "" });
        closeNamePopup();
    };

    if (nameSave) nameSave.addEventListener("click", doSaveName);
    if (nameInput) {
        nameInput.addEventListener("keydown", (e) => {
            if (e.key !== "Enter") return;
            e.preventDefault();
            doSaveName();
        });
    }

    $("modal-confirm").addEventListener("click", () => {
        if (!currentModal) return closeModal();
        postNui("modalResponse", { modalId: currentModal.modalId, accepted: true });
        closeModal();
    });

    $("modal-cancel").addEventListener("click", () => {
        if (!currentModal) return closeModal();
        postNui("modalResponse", { modalId: currentModal.modalId, accepted: false });
        closeModal();
    });

    $("modal-backdrop").addEventListener("click", () => {
        // Close modal without accepting; Lua will also release focus on modalResponse.
        if (!currentModal) return closeModal();
        postNui("modalResponse", { modalId: currentModal.modalId, accepted: false });
        closeModal();
    });

    document.addEventListener("keydown", (e) => {
        if (e.key !== "Escape") return;

        // ESC closes modal first; otherwise closes UI.
        if (!$("modal").classList.contains("hidden")) {
            if (currentModal) postNui("modalResponse", { modalId: currentModal.modalId, accepted: false });
            closeModal();
            return;
        }

        // ESC closes rename popup next.
        if (!$("name-popup").classList.contains("hidden")) {
            closeNamePopup();
            return;
        }

        if (!$("contract-container").classList.contains("hidden")) {
            postNui("closeUI", {});
        }
    });

    // Initial paint
    setRigNameUI(currentRigName);
});
