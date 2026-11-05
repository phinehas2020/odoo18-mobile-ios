# Apple HIG interface review — October 7, 2026

The app now uses current native iOS navigation, glass floating controls, semantic system surfaces and more compact operational lists. Quantity controls and fields identify their products to VoiceOver, large-text layouts scroll and stack, edited forms protect drafts, and save/search failures provide clear recovery.

All 57 native tests passed after the final changes. These are simulator captures with fixture data, not live customer orders. CoreDevice confirmed installation and successful launch on the iPhone Air.

## Screen captures

| Area | Review |
| --- | --- |
| Work | [Light](ux-work.png), [dark](ux-work-dark.png), [compact width](ux-work-compact.png), [largest text](ux-work-accessibility5.png) |
| Warehouse | [Main screen](ux-warehouse.png), [receipt](ux-receipt-light.png), [dark receipt](ux-receipt-dark.png), [production completion](production-completion-review.png) |
| Packing | [Light](packing-checklist-light.png), [dark](packing-checklist-dark.png), [high contrast](packing-high-contrast-dark.png), [largest text](packing-checklist-accessibility5.png) |
| Label scanner | [Largest text](ux-scanner-accessibility5.png), [controls after scrolling](ux-scanner-accessibility5-controls.png), [landscape controls](ux-scanner-landscape-controls.png) |
| Product scanner | [Largest text](ux-product-scanner-accessibility5.png), [landscape](ux-product-scanner-landscape.png) |
| Sales and account | [Sales](ux-sales.png), [settings](ux-settings.png), [login](ux-login.png), [dark login](ux-login-dark.png), [largest-text login](ux-login-accessibility5.png) |

The camera toolbar keeps white controls and a readable title over the preview through native toolbar appearance. Scanner panels remain scrollable in large text and landscape; preview fixtures start no camera and submit no tracking/product code.

## Evidence and recovery

The [implementation report](/Users/phinehasadams/homestead-gristmill-os/outputs/reports/apple-hig-app-update-2026-10-07.md) ties changes to Apple’s guidance, records verification and lists rollback material. The [source register](sources.json) includes 46 relevant HIG article URLs reviewed across the audit team. Older iOS fallbacks are availability-checked; this session’s runtime is iOS27.

The standard Xcode test-service startup failed; the existing compiled XCTest bundle executed successfully in the app host through Apple’s XCTest injection runtime. All 57 tests and their assertions remained intact. Physical VoiceOver/keyboard and notification-delivery acceptance are separate from these renders and source checks. The working camera controller, packing gates and transaction payloads were preserved; business completion policy was not changed.
