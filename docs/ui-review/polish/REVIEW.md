# Native app UI polish — October 5, 2026

The app uses one operational style throughout: a warm canvas, forest-green accents, consistent icon tiles, clear state colors and plain instructions. Light/dark appearances and Dynamic Type keep the native controls and navigation.

## Changed surfaces

| Area | What changed | Screenshot |
| --- | --- | --- |
| Work and production | Product-first order rows, visible state and quantity, clearer materials, operation steps and quality forms | [Work](ux-work.png), [dark](ux-work-dark.png), [large text](ux-work-large-text.png), [completion](production-completion-review.png) |
| Warehouse | Shipping and picking entry point, consistent receipt/transfer rows, clearer received and remaining quantities, improved return/count/scrap review forms | [Warehouse](ux-warehouse.png), [receipt](ux-receipt-light.png), [dark receipt](ux-receipt-dark.png) |
| Packing and scanning | Box/order hierarchy, picked units and packed boxes, larger confirmation controls, clearer scan instructions and preview/offline notices | [Packing](packing-checklist-light.png), [dark](packing-checklist-dark.png), [accessible review](packing-review-accessibility.png) |
| Sales and customers | Customer/order hierarchy, named status badges, easier contact and note forms | [Sales](ux-sales.png) |
| Account and settings | Labeled sign-in fields, full-width sign-in button, account summary and collapsible connection/support details | [Login](ux-login.png), [dark login](ux-login-dark.png), [settings](ux-settings.png), [More](ux-more.png) |

At accessibility text sizes, shared introductory and action rows give the width to text. Production rows stack status and quantity. Filled buttons keep a dark fill so their white labels remain readable in dark mode.

## Verification and scope

All 50 native tests passed after the integrated changes and production-row layout correction. All six affected rendering checks passed again after the final accessibility header adjustment. Screens here are simulator captures using disposable fixture data; they are not production order/customer screenshots or evidence of physical packing completion.

An independent comparison against the exact pre-polish source archive confirmed that 27 Core files and 10 ViewModels were unchanged. The shared camera controller and its corrected detection geometry were unchanged. Existing packing, inventory, production and quality validation, payloads and completion/edit/offline gates were preserved. The added retry controls only reload data; the sales empty-note button guard matches the existing submission guard.

No backend deployment, business completion setting, inventory transaction, print job or customer notification was performed for this UI pass. Source edits remain in the existing app checkout; this pass did not commit or push the app repository.

The source checkpoint, before/after SHA-256 manifests, UI-only patch and signed app recovery copies are recorded in the [operations recovery report](/Users/phinehasadams/homestead-gristmill-os/outputs/reports/phone-packing-recovery-2026-10-05.md).

## iPhone update

The signed device build passed strict signature verification and installed successfully on the paired iPhone Air. The automatic launch check was blocked because the phone was locked. These simulator renders do not replace the employee’s physical phone review.
