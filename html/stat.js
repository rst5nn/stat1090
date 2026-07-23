/**
 * stat1090 Frontend Controller
 * Handles exact time range selection (From & Till), presets, auto-refresh, modal zoom, and theme toggling.
 */

// Application State
let currentMode = 'preset'; // 'preset' or 'custom'
let activePreset = '2h';
let customFrom = null;
let customTill = null;
let refreshTimer = null;
let refreshIntervalSeconds = parseInt(localStorage.getItem('stat1090_refresh') || '60', 10);
let activeTheme = localStorage.getItem('stat1090_theme') || 'dark';

const GRAPH_TYPES = ['range', 'signal', 'aircraft'];

const PRESET_LABELS = {
    '2h': 'Last 2 Hours',
    '8h': 'Last 8 Hours',
    '24h': 'Last 24 Hours'
};

document.addEventListener('DOMContentLoaded', () => {
    initTheme();
    initDateTimeInputs();
    parseUrlParameters();
    initRefreshButtons();
    refreshGraphs();
    startAutoRefresh();
});

/**
 * Initialize theme state on load
 */
function initTheme() {
    applyTheme(activeTheme);
}

/**
 * Toggle between Dark and Bright (Light) themes
 */
function toggleTheme() {
    activeTheme = (activeTheme === 'dark') ? 'light' : 'dark';
    localStorage.setItem('stat1090_theme', activeTheme);
    applyTheme(activeTheme);
    refreshGraphs();
}

/**
 * Apply theme to document attribute and update toggle UI
 */
function applyTheme(theme) {
    document.documentElement.setAttribute('data-theme', theme);

    const sunIcon = document.getElementById('theme-icon-sun');
    const moonIcon = document.getElementById('theme-icon-moon');
    const toggleText = document.getElementById('theme-toggle-text');

    if (theme === 'light') {
        if (sunIcon) sunIcon.style.display = 'none';
        if (moonIcon) moonIcon.style.display = 'inline-block';
        if (toggleText) toggleText.textContent = 'Dark Theme';
    } else {
        if (sunIcon) sunIcon.style.display = 'inline-block';
        if (moonIcon) moonIcon.style.display = 'none';
        if (toggleText) toggleText.textContent = 'Bright Theme';
    }
}

/**
 * Initialize datetime-local inputs with 24-hour military default (last 2 hours).
 */
function initDateTimeInputs() {
    const now = new Date();
    const past2h = new Date(now.getTime() - (2 * 60 * 60 * 1000));

    document.getElementById('till-time').value = toDatetimeLocalString(now);
    document.getElementById('from-time').value = toDatetimeLocalString(past2h);
}

/**
 * Helper to convert Date object to format required by <input type="datetime-local"> (YYYY-MM-DDTHH:mm)
 */
function toDatetimeLocalString(date) {
    const pad = (n) => n < 10 ? '0' + n : n;
    const year = date.getFullYear();
    const month = pad(date.getMonth() + 1);
    const day = pad(date.getDate());
    const hours = pad(date.getHours());
    const minutes = pad(date.getMinutes());
    return `${year}-${month}-${day}T${hours}:${minutes}`;
}

/**
 * Parse URL params to support deep linking with ?from=...&till=... or ?preset=...
 */
function parseUrlParameters() {
    const params = new URLSearchParams(window.location.search);
    
    if (params.has('from') && params.has('till')) {
        currentMode = 'custom';
        customFrom = params.get('from');
        customTill = params.get('till');

        document.getElementById('from-time').value = customFrom;
        document.getElementById('till-time').value = customTill;

        document.querySelectorAll('.btn-preset').forEach(btn => btn.classList.remove('active'));
    } else if (params.has('preset') || params.has('timeframe')) {
        const preset = params.get('preset') || params.get('timeframe');
        if (PRESET_LABELS[preset]) {
            selectPreset(preset, false);
        }
    }
}

/**
 * Handle quick preset button click
 */
function selectPreset(presetKey, triggerRefresh = true) {
    currentMode = 'preset';
    activePreset = presetKey;

    // Highlight active preset button
    document.querySelectorAll('.btn-preset').forEach(btn => {
        if (btn.getAttribute('data-range') === presetKey) {
            btn.classList.add('active');
        } else {
            btn.classList.remove('active');
        }
    });

    const now = new Date();
    let fromDate = new Date();
    const hoursMatch = presetKey.match(/^(\d+)h$/);

    if (hoursMatch) {
        fromDate.setTime(now.getTime() - parseInt(hoursMatch[1], 10) * 3600 * 1000);
    }

    document.getElementById('till-time').value = toDatetimeLocalString(now);
    document.getElementById('from-time').value = toDatetimeLocalString(fromDate);

    updateUrlParams({ preset: presetKey, from: null, till: null });

    if (triggerRefresh) {
        refreshGraphs();
    }
}

/**
 * Apply custom From & Till range submitted via form
 */
function applyCustomRange(event) {
    if (event) event.preventDefault();

    const fromVal = document.getElementById('from-time').value;
    const tillVal = document.getElementById('till-time').value;

    if (!fromVal || !tillVal) {
        alert('Please select both From and Till date-time values.');
        return;
    }

    const fromDate = new Date(fromVal);
    const tillDate = new Date(tillVal);

    if (fromDate >= tillDate) {
        alert('The "From" (Start) date-time must be earlier than "Till" (End) date-time.');
        return;
    }

    currentMode = 'custom';
    customFrom = fromVal;
    customTill = tillVal;

    document.querySelectorAll('.btn-preset').forEach(btn => btn.classList.remove('active'));

    updateUrlParams({ from: fromVal, till: tillVal, preset: null });

    refreshGraphs();
}

/**
 * Quick button to set "Till" input to right now and re-apply range
 */
function setLiveNow() {
    const now = new Date();
    document.getElementById('till-time').value = toDatetimeLocalString(now);
    applyCustomRange();
}

/**
 * Update browser URL without reloading page
 */
function updateUrlParams(paramsObj) {
    const url = new URL(window.location);
    Object.keys(paramsObj).forEach(key => {
        if (paramsObj[key] === null) {
            url.searchParams.delete(key);
        } else {
            url.searchParams.set(key, paramsObj[key]);
        }
    });
    window.history.replaceState({}, '', url);
}

/**
 * Helper to get the correct API URL depending on root (/) or subpath (/stat1090/) deployment
 */
function getApiGraphUrl(type, fromQuery, tillQuery, timestamp) {
    let basePath = window.location.pathname;
    basePath = basePath.replace(/\/index\.html$/, '');
    if (!basePath.endsWith('/')) {
        basePath += '/';
    }
    const endpoint = `${basePath}api/graph`;
    return `${endpoint}?type=${type}&from=${encodeURIComponent(fromQuery)}&till=${encodeURIComponent(tillQuery)}&theme=${encodeURIComponent(activeTheme)}&_t=${timestamp}`;
}

/**
 * Refresh graph images based on active state (Preset or Custom Range)
 */
function refreshGraphs() {
    const timestamp = Math.floor(Date.now() / 1000);

    let fromQuery = activePreset;
    let tillQuery = 'now';
    let displayRangeText = '';

    const modeBadge = document.getElementById('mode-badge');
    const rangeDisplay = document.getElementById('active-range-display');

    if (currentMode === 'custom' && customFrom && customTill) {
        fromQuery = customFrom;
        tillQuery = customTill;
        displayRangeText = `${formatDateDisplay(customFrom)}  ➜  ${formatDateDisplay(customTill)}`;
        if (modeBadge) {
            modeBadge.textContent = 'CUSTOM';
            modeBadge.className = 'badge badge-custom';
        }
    } else {
        displayRangeText = PRESET_LABELS[activePreset] || activePreset;
        if (modeBadge) {
            modeBadge.textContent = 'PRESET';
            modeBadge.className = 'badge badge-accent';
        }
    }

    if (rangeDisplay) {
        rangeDisplay.textContent = displayRangeText;
    }

    // Fetch and reload each of the 5 graphs
    GRAPH_TYPES.forEach(type => {
        const loader = document.getElementById(`loader-${type}`);
        const img = document.getElementById(`img-${type}`);

        if (loader) loader.classList.add('active');

        const srcUrl = getApiGraphUrl(type, fromQuery, tillQuery, timestamp);

        const tempImg = new Image();
        tempImg.onload = () => {
            if (img) img.src = srcUrl;
            if (loader) loader.classList.remove('active');
        };
        tempImg.onerror = () => {
            if (loader) loader.classList.remove('active');
        };
        tempImg.src = srcUrl;
    });

    // Update timestamp badge in 24-hour military time (e.g. 17:08:29)
    const timeStr = formatMilitaryTime(new Date());
    const updatedBadge = document.getElementById('last-updated');
    if (updatedBadge) {
        updatedBadge.textContent = `Updated: ${timeStr}`;
    }
}

function formatMilitaryTime(d = new Date()) {
    const pad = (n) => n < 10 ? '0' + n : n;
    return `${pad(d.getHours())}:${pad(d.getMinutes())}:${pad(d.getSeconds())}`;
}

function formatDateDisplay(isoStr) {
    if (!isoStr) return '';
    const d = new Date(isoStr);
    if (isNaN(d.getTime())) return isoStr;
    const pad = (n) => n < 10 ? '0' + n : n;
    return `${d.getFullYear()}-${pad(d.getMonth()+1)}-${pad(d.getDate())} ${pad(d.getHours())}:${pad(d.getMinutes())}`;
}

/**
 * Handle auto-refresh interval buttons UI and state
 */
function initRefreshButtons() {
    updateRefreshButtonUI(refreshIntervalSeconds);
}

function setRefreshInterval(valSeconds) {
    refreshIntervalSeconds = parseInt(valSeconds, 10);
    localStorage.setItem('stat1090_refresh', refreshIntervalSeconds);
    updateRefreshButtonUI(refreshIntervalSeconds);
    startAutoRefresh();
}

function updateRefreshButtonUI(seconds) {
    document.querySelectorAll('.btn-refresh').forEach(btn => {
        const intervalVal = parseInt(btn.getAttribute('data-interval'), 10);
        if (intervalVal === seconds) {
            btn.classList.add('active');
        } else {
            btn.classList.remove('active');
        }
    });
}

function startAutoRefresh() {
    if (refreshTimer) {
        clearInterval(refreshTimer);
        refreshTimer = null;
    }

    if (refreshIntervalSeconds > 0) {
        refreshTimer = setInterval(() => {
            if (currentMode === 'preset') {
                const now = new Date();
                document.getElementById('till-time').value = toDatetimeLocalString(now);
            }
            refreshGraphs();
        }, refreshIntervalSeconds * 1000);
    }
}

/**
 * Save/Download Graph PNG Image with formatted filename
 */
function saveGraphImage(type, buttonEl) {
    const imgEl = document.getElementById(`img-${type}`);
    if (!imgEl || !imgEl.src) return;

    const filename = generateSaveFilename(type);

    fetch(imgEl.src)
        .then(response => response.blob())
        .then(blob => {
            const blobUrl = URL.createObjectURL(blob);
            const a = document.createElement('a');
            a.href = blobUrl;
            a.download = filename;
            document.body.appendChild(a);
            a.click();
            document.body.removeChild(a);
            setTimeout(() => URL.revokeObjectURL(blobUrl), 1000);
        })
        .catch(err => {
            console.error('Failed to download graph image:', err);
            const a = document.createElement('a');
            a.href = imgEl.src;
            a.download = filename;
            a.target = '_blank';
            a.click();
        });
}

function generateSaveFilename(type) {
    const now = new Date();
    const tillStr = formatDateNoColons(now);
    let fromStr = '';

    if (currentMode === 'custom' && customFrom && customTill) {
        const dFrom = new Date(customFrom);
        const dTill = new Date(customTill);
        if (!isNaN(dFrom.getTime())) {
            fromStr = formatDateNoColons(dFrom);
        } else {
            fromStr = String(customFrom).replace(/:/g, '');
        }
        if (!isNaN(dTill.getTime())) {
            tillStr = formatDateNoColons(dTill);
        } else {
            tillStr = String(customTill).replace(/:/g, '');
        }
    } else {
        let durationMs = 2 * 60 * 60 * 1000; // default 2h
        if (activePreset === '2h') durationMs = 2 * 60 * 60 * 1000;
        else if (activePreset === '8h') durationMs = 8 * 60 * 60 * 1000;
        else if (activePreset === '24h') durationMs = 24 * 60 * 60 * 1000;

        const dFrom = new Date(now.getTime() - durationMs);
        fromStr = formatDateNoColons(dFrom);
    }

    return `stat1090_${type}_${fromStr}_${tillStr}.png`;
}

function formatDateNoColons(dObj) {
    const pad = (n) => n < 10 ? '0' + n : n;
    return `${dObj.getFullYear()}-${pad(dObj.getMonth()+1)}-${pad(dObj.getDate())}T${pad(dObj.getHours())}${pad(dObj.getMinutes())}`;
}

/**
 * Modal Lightbox Viewer
 */
function openModal(graphType) {
    let fromQuery = activePreset;
    let tillQuery = 'now';

    if (currentMode === 'custom' && customFrom && customTill) {
        fromQuery = customFrom;
        tillQuery = customTill;
    }

    const timestamp = Math.floor(Date.now() / 1000);
    const srcUrl = getApiGraphUrl(graphType, fromQuery, tillQuery, timestamp);

    const titles = {
        'range': 'Range (Nautical Miles)',
        'signal': 'Signal Level (dBFS)',
        'aircraft': 'Aircraft Tracked',
        'messages': 'Message Rate (Messages/Second)',
        'tracks': 'Tracks Seen (Tracks/Hour)'
    };

    document.getElementById('modal-title').textContent = titles[graphType] || 'Graph Details';
    document.getElementById('modal-img').src = srcUrl;
    document.getElementById('graph-modal').classList.add('active');
}

function closeModal(event) {
    document.getElementById('graph-modal').classList.remove('active');
}
