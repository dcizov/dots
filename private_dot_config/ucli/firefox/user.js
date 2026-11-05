//
// Betterfox user.js — vendored from https://github.com/yokoffing/Betterfox (v154)
// Plus user overrides below the "MY OVERRIDES" marker.
//
// You may copy+paste this file and use it as it is.
//
// If you make changes to your about:config while the program is running, the
// changes will be overwritten by the user.js when the application restarts.
//
// To make lasting changes to preferences, you will have to edit the user.js.
//

/****************************************************************************
 * Betterfox                                                                *
 * "Ad meliora"                                                             *
 * version: 154                                                             *
 * url: https://github.com/yokoffing/Betterfox                              *
****************************************************************************/

/****************************************************************************
 * SECTION: FASTFOX                                                         *
****************************************************************************/
/** GENERAL **/
user_pref("gfx.content.skia-font-cache-size", 20);
user_pref("content.notify.interval", 100000);

/** GFX **/
user_pref("gfx.canvas.accelerated.cache-size", 512);

/** MEDIA CACHE **/
user_pref("media.cache_readahead_limit", 3600);
user_pref("media.cache_resume_threshold", 1800);

/** IMAGE CACHE **/
user_pref("image.mem.decode_bytes_at_a_time", 32768);

/** NETWORKING **/
user_pref("network.buffer.cache.size", 65535);
user_pref("network.buffer.cache.count", 48);
user_pref("network.http.max-connections", 1800);
user_pref("network.http.max-persistent-connections-per-server", 10);
user_pref("network.http.max-urgent-start-excessive-connections-per-host", 5);
user_pref("network.http.request.max-start-delay", 5);
user_pref("network.dnsCacheExpiration", 3600);

/****************************************************************************
 * SECTION: SECUREFOX                                                       *
****************************************************************************/
/** TRACKING PROTECTION ***/
user_pref("browser.contentblocking.category", "strict");
user_pref("browser.download.start_downloads_in_tmp_dir", true);
user_pref("browser.uitour.enabled", false);
user_pref("privacy.globalprivacycontrol.enabled", true);

/** OCSP & CERTS / HPKP ***/
user_pref("security.OCSP.enabled", 0);
user_pref("privacy.antitracking.isolateContentScriptResources", true);
user_pref("security.csp.reporting.enabled", false);

/** SSL / TLS ***/
user_pref("security.ssl.treat_unsafe_negotiation_as_broken", true);
user_pref("browser.xul.error_pages.expert_bad_cert", true);
user_pref("security.tls.enable_0rtt_data", false);

/** DISK AVOIDANCE ***/
user_pref("browser.cache.disk.enable", false);
user_pref("browser.privatebrowsing.forceMediaMemoryCache", true);
user_pref("media.memory_cache_max_size", 65536);
user_pref("browser.sessionstore.interval", 60000);

/** SHUTDOWN & SANITIZING ***/
user_pref("privacy.history.custom", true);

/** SPECULATIVE LOADING ***/
user_pref("network.http.speculative-parallel-limit", 0);
user_pref("network.dns.disablePrefetch", true);
user_pref("network.dns.disablePrefetchFromHTTPS", true);
user_pref("browser.urlbar.speculativeConnect.enabled", false);
user_pref("browser.places.speculativeConnect.enabled", false);
user_pref("network.prefetch-next", false);

/** SEARCH / URL BAR ***/
user_pref("browser.urlbar.trimHttps", true);
user_pref("browser.urlbar.untrimOnUserInteraction.featureGate", true);
user_pref("browser.search.separatePrivateDefault.ui.enabled", true);
user_pref("browser.search.suggest.enabled", false);
user_pref("browser.urlbar.quicksuggest.enabled", false);
user_pref("browser.urlbar.groupLabels.enabled", false);
user_pref("browser.formfill.enable", false);
user_pref("network.IDN_show_punycode", true);

/** HTTPS-ONLY MODE ***/
user_pref("dom.security.https_only_mode", true);
user_pref("dom.security.https_only_mode_error_page_user_suggestions", true);

/** PASSWORDS ***/
user_pref("signon.formlessCapture.enabled", false);
user_pref("signon.privateBrowsingCapture.enabled", false);
user_pref("network.auth.subresource-http-auth-allow", 1);
user_pref("editor.truncate_user_pastes", false);

/** EXTENSIONS ***/
/* 2660: only load extensions from the profile and application directories
 * (1 = profile, 4 = application). Extensions dropped anywhere else are ignored. ***/
user_pref("extensions.enabledScopes", 5);
/* 2661: extensions dropped into a directory by an outside program are
 * installed but DISABLED by default (bit flags: 1 = profile, 2 = user,
 * 4 = application, 8 = system; default 15 = every scope).
 *
 * Betterfox lowers this to 14 so that files dropped into a profile are imported
 * enabled. This repo does not need that and does not want it: extensions are
 * installed through Firefox's own policies (/etc/firefox/policies/policies.json,
 * written by `ucli firefox-policies`), which installs *and* enables them without
 * touching a profile. Keeping the default is the safe direction — an add-on that
 * some other program drops into a scope must not silently come up enabled. ***/

/** HEADERS / REFERERS ***/
user_pref("network.http.referer.XOriginTrimmingPolicy", 2);

/** VARIOUS ***/
user_pref("pdfjs.enableScripting", false);

/** SAFE BROWSING ***/
user_pref("browser.safebrowsing.downloads.remote.enabled", false);

/** MOZILLA ***/
user_pref("permissions.default.desktop-notification", 2);
user_pref("permissions.default.geo", 2);
user_pref("geo.provider.network.url", "https://beacondb.net/v1/geolocate");
user_pref("browser.search.update", false);
user_pref("permissions.manager.defaultsUrl", "");
user_pref("extensions.getAddons.cache.enabled", false);

/** TELEMETRY ***/
user_pref("datareporting.policy.dataSubmissionEnabled", false);
user_pref("datareporting.healthreport.uploadEnabled", false);
user_pref("toolkit.telemetry.unified", false);
user_pref("toolkit.telemetry.enabled", false);
user_pref("toolkit.telemetry.server", "data:,");
user_pref("toolkit.telemetry.archive.enabled", false);
user_pref("toolkit.telemetry.newProfilePing.enabled", false);
user_pref("toolkit.telemetry.shutdownPingSender.enabled", false);
user_pref("toolkit.telemetry.updatePing.enabled", false);
user_pref("toolkit.telemetry.bhrPing.enabled", false);
user_pref("toolkit.telemetry.firstShutdownPing.enabled", false);
user_pref("toolkit.telemetry.coverage.opt-out", true);
user_pref("toolkit.coverage.opt-out", true);
user_pref("toolkit.coverage.endpoint.base", "");
user_pref("browser.newtabpage.activity-stream.feeds.telemetry", false);
user_pref("browser.newtabpage.activity-stream.telemetry", false);
user_pref("datareporting.usage.uploadEnabled", false);

/** EXPERIMENTS ***/
user_pref("app.shield.optoutstudies.enabled", false);
user_pref("app.normandy.enabled", false);
user_pref("app.normandy.api_url", "");
user_pref("nimbus.rollouts.enabled", false);

/** CRASH REPORTS ***/
user_pref("breakpad.reportURL", "");
user_pref("browser.tabs.crashReporting.sendReport", false);
user_pref("browser.crashReports.unsubmittedCheck.enabled", false);

/****************************************************************************
 * SECTION: PESKYFOX                                                        *
****************************************************************************/
/** MOZILLA UI ***/
user_pref("extensions.getAddons.showPane", false);
user_pref("extensions.htmlaboutaddons.recommendations.enabled", false);
user_pref("browser.discovery.enabled", false);
user_pref("browser.shell.checkDefaultBrowser", false);
user_pref("browser.newtabpage.activity-stream.asrouter.userprefs.cfr.addons", false);
user_pref("browser.newtabpage.activity-stream.asrouter.userprefs.cfr.features", false);
user_pref("browser.preferences.moreFromMozilla", false);
user_pref("browser.aboutConfig.showWarning", false);
user_pref("browser.startup.homepage_override.mstone", "ignore");
user_pref("browser.aboutwelcome.enabled", false);
user_pref("browser.profiles.enabled", true);

/** THEME ADJUSTMENTS ***/
user_pref("toolkit.legacyUserProfileCustomizations.stylesheets", true);
user_pref("browser.compactmode.show", true);
user_pref("browser.privateWindowSeparation.enabled", false); // WINDOWS

/** AI ***/
user_pref("browser.ai.control.default", "blocked");
user_pref("browser.ml.enable", false);
user_pref("browser.ml.chat.enabled", false);
user_pref("browser.ml.chat.menu", false);
user_pref("browser.tabs.groups.smart.enabled", false);
user_pref("browser.ml.linkPreview.enabled", false);

/** FULLSCREEN NOTICE ***/
user_pref("full-screen-api.transition-duration.enter", "0 0");
user_pref("full-screen-api.transition-duration.leave", "0 0");

/****************************************************************************
 * SECTION: SMOOTHFOX                                                       *
****************************************************************************/
// visit https://github.com/yokoffing/Betterfox/blob/main/Smoothfox.js
// Option: SHARPEN SCROLLING (recommended for general use)
user_pref("full-screen-api.warning.timeout", 0);

/** URL BAR ***/
user_pref("browser.urlbar.trending.featureGate", false);

/** NEW TAB PAGE ***/
user_pref("browser.newtabpage.activity-stream.default.sites", "");
user_pref("browser.newtabpage.activity-stream.showSponsoredTopSites", false);
user_pref("browser.newtabpage.activity-stream.feeds.section.topstories", false);
user_pref("browser.newtabpage.activity-stream.showSponsored", false);
user_pref("browser.newtabpage.activity-stream.showSponsoredCheckboxes", false);

/** DOWNLOADS ***/
user_pref("browser.download.manager.addToRecentDocs", false);

/** PDF ***/
user_pref("browser.download.open_pdf_attachments_inline", true);

/** TAB BEHAVIOR ***/
user_pref("browser.bookmarks.openInTabClosesMenu", false);
user_pref("findbar.highlightAll", true);

/** Smoothfox: sharpen scrolling **/
user_pref("apz.overscroll.enabled", true); // DEFAULT NON-LINUX
user_pref("general.smoothScroll", true); // DEFAULT
user_pref("mousewheel.min_line_scroll_amount", 10); // adjust this number to your liking; default=5
user_pref("general.smoothScroll.mouseWheel.durationMinMS", 80); // default=50
user_pref("general.smoothScroll.currentVelocityWeighting", "0.15"); // default=.25
user_pref("general.smoothScroll.stopDecelerationWeighting", "0.6"); // default=.4
user_pref("apz.gtk.kinetic_scroll.delta_mode", 2);
user_pref("apz.gtk.pangesture.delta_mode", 2);
user_pref("apz.gtk.kinetic_scroll.pixel_delta_mode_multiplier", 25);
user_pref("apz.gtk.pangesture.pixel_delta_mode_multiplier", 25);
user_pref("apz.fling_friction", 0.004);

/****************************************************************************
 * START: MY OVERRIDES                                                      *
****************************************************************************/
// User's Betterfox choices (v154):
//   - Tracking Protection: strict (custom features string, -lvl2 for less breakage)
//   - Location requests: allowed (permissions.default.geo = 0)
//   - Unified search button: disabled
//   - Container tabs: enabled
//   - Login manager: disabled (use Bitwarden)
//   - Address/credit card manager: disabled
//   - Passkeys: disabled
//   - Secure DNS: Max Protection (mode 3) — custom URI removed (didn't work)
//   - New tab: hide topsites, weather, dropdown suggestions
//   - Certificate pinning: REMOVED (level 2 breaks with antivirus/captive portals)
//   - Sanitize on close: cookies + cache only (keep history)
//   - Service workers: RE-ENABLED (was breaking PWAs/push notifications)
//   - JavaScript JIT: RE-ENABLED (ion + wasm — Betterfox does not disable; too much breakage)
//   - GTK kinetic scroll: pixel-based scrolling tuned (Smoothfox)

// --- Tracking Protection: strict, less aggressive (-lvl2 removed) ---
user_pref("browser.contentblocking.features.strict", "tp,tpPrivate,cookieBehavior5,cookieBehaviorPBM5,cryptoTP,fp,stp,emailTP,emailTPPrivate,-consentmanagerSkip,-consentmanagerSkipPrivate,-lvl2,rp,rpTop,qps,qpsPBM,fpp,fppPrivate,btp,lna");

// --- Location requests: allowed ---
user_pref("permissions.default.geo", 0);

// --- Unified search button: disabled ---
user_pref("browser.urlbar.scotchBonnet.enableOverride", false);

// --- Container tabs: enabled ---
user_pref("privacy.userContext.enabled", true);

// --- Login manager: disabled ---
user_pref("signon.rememberSignons", false);

// --- Address & credit card manager: disabled ---
user_pref("extensions.formautofill.addresses.enabled", false);
user_pref("extensions.formautofill.creditCards.enabled", false);

// --- Passkeys: disabled ---
user_pref("security.webauth.webauthn", false);

// --- Secure DNS: Max Protection (mode 3) + AdGuard DoH ---
user_pref("network.trr.mode", 3);
user_pref("network.trr.uri", "https://dns.adguard-dns.com/dns-query");

// --- New tab: hide topsites, weather, dropdown suggestions ---
user_pref("browser.newtabpage.activity-stream.feeds.topsites", false);
user_pref("browser.newtabpage.activity-stream.showWeather", false);
user_pref("browser.urlbar.suggest.topsites", false);

// --- Sanitize on close: cookies + cache only (keep history) ---
user_pref("privacy.sanitize.sanitizeOnShutdown", true);
user_pref("privacy.clearOnShutdown_v2.cache", true);
user_pref("privacy.clearOnShutdown_v2.cookiesAndStorage", true);
user_pref("privacy.clearOnShutdown_v2.browsingHistoryAndDownloads", false);
user_pref("privacy.clearOnShutdown_v2.downloads", false);
user_pref("privacy.clearOnShutdown_v2.formdata", true);

/****************************************************************************
 // --- ResistFingerprinting (via Fingerprinting Protection + overrides) ---
// Use privacy.fingerprintingProtection instead of privacy.resistFingerprinting
// so we can selectively override individual protections that cause breakage.
// +AllTargets = enable all fingerprinting protections (equivalent to RFP)
// -CSSPrefersColorScheme = allow websites to see your color scheme (dark/white theme works)
//
// Other override targets you can remove (each reduces fingerprinting protection):
//   -JSDateTimeUTC        don't spoof timezone to UTC (fixes calendars/scheduling)
//   -WebGLRenderCapability don't mask WebGL capabilities (fixes WebGL rendering)
//   -SiteSpecificZoom     allow per-site zoom level memory
//   -FrameRate            allow frame rate reporting
//   -KeyboardEvents       allow keyboard event reporting
//   -CanvasExtractionBeforeUserInputIsBlocked allow canvas readback without user input
//
// Site-specific exceptions via granularOverrides (JSON array):
//   [{"firstPartyDomain":"example.com","overrides":"-WebGLRenderCapability,-CanvasExtractionBeforeUserInputIsBlocked"}]
//
// Note: privacy.resistFingerprinting must be FALSE for FPP overrides to take effect.
// RFP is all-or-nothing; FPP is the granular replacement.
user_pref("privacy.resistFingerprinting", false);
user_pref("privacy.fingerprintingProtection", true);
user_pref("privacy.fingerprintingProtection.overrides", "+AllTargets,-CSSPrefersColorScheme");

// --- layout.css.prefers-color-scheme.content-override ---
// 0 = force dark, 1 = force light, 2 = system, 3 = theme colors
// Kept at default (2=system) so sites respect your OS/theme preference.
// With -CSSPrefersColorScheme above, this preference is honored by websites.

 * END: BETTERFOX                                                           *
 ****************************************************************************/