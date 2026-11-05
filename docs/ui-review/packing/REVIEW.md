# Shipping label picking review

October 5, 2026. Native iOS implementation tested with disposable mocked responses; no production completion, inventory, payment, label purchase, printing, or Shopify request was made.

Warehouse shows **Pack orders** when the authenticated menu includes the enabled native packing feature. The employee scans a shipping label, confirms the quantities for its specific box, taps **Scan to finish this box**, and scans the same label in a fresh session. The server decides ownership, eligibility, box contents, and every completion state. Labels from another box cannot submit completion.

The camera applies a real detection region matching the visible frame, reports every unique candidate in that frame with its symbology, and waits for server resolution rather than choosing the first barcode. The existing inventory scanner still calls its existing product confirmation handler; when multiple product barcodes are detected it asks the operator to choose one. Camera denial and unavailable hardware have manual entry fallbacks.

The native preview flag can expose label lookup independently of the business cutover. `business_enabled` must be explicitly true before the app allows any progress or finish action. Preview displays a clear notice, and legacy records show **Order preview** with server review details. Physical picking can remain unfinished on reconciled orders whose local operational effects were already verified; the app follows authoritative allowed actions without claiming the box is packed.

Picking progress uses absolute quantities and the current order version. Completion is a direct online request with a new event ID and the signed device ID. The app never queues packing completion in the stock outbox. If a response is lost, edits and finish scans stop until a fresh server read. A device-, user-, and company-bound interrupted-completion marker survives restart and triggers reads only. It contains no customer details or tracking barcode.

Completion copy distinguishes **Box packed**, **Packed — tracking update pending**, **Ready to ship**, and **Packed — review needed**. Ready to ship requires the server to confirm physical packing, operational completion, and the store's tracking sync. Unsupported workflow/state values keep write actions disabled. Existing legacy shipping records stay behind server review rules.

## Verification

Using the installed `/Applications/Xcode-beta.app` explicitly (without changing the user's global Xcode selection), the app and selected simulator tests compiled and ran on the Odoo Mobile Review iPhone, iOS 27.0.

- All 24 selected tests passed on the final source, zero failures: 13 packing workflow tests, one packing rendering test covering three states, seven warehouse/scanner regressions, and three networking diagnostics regressions. The final test result is `/private/tmp/packing-ios-build/Logs/Test/Test-MobileOdoo-2026.10.05_12-09-23--0500.xcresult`.
- Tests cover read-only candidate lookup, deliberate finish gating, wrong labels, absolute versioned progress, simultaneous camera callbacks, lost-response reconciliation, restart recovery, offline/ownership blocks, specific business holds, candidate deduplication, the detection frame, and multi-box/review status copy.
- Light mode, dark mode, and accessibility text size screenshots were captured from mocked fixtures and visually inspected. Rows and review messages remain scrollable and readable.
- Existing uncommitted Home and warehouse UI work was preserved. Comparison with the captured source baseline showed only packing navigation additions to Home.
- A signed arm64 iPhone app compiled successfully using the existing local team and provisioning profile. The build artifact is `/private/tmp/packing-ios-device/Build/Products/Debug-iphoneos/MobileOdoo.app`; this workstream did not install it or request provisioning updates.
- A signed rollback app was built from the protected pre-change source archive, including the captured uncommitted UI. Both old and new app bundles passed strict signature verification and were saved under the private baseline backup with per-file hashes, content tree hashes, and build metadata.

Actual USPS, UPS, and FedEx printed-label camera readability still requires a physical iPhone check. The Simulator cannot establish real camera success, glare handling, or first-attempt resolution rates. Server-side stock/accounting/provider behavior and production cutover are verified separately by the backend workstream.

Screenshots: [light](packing-checklist-light.png), [dark](packing-checklist-dark.png), [accessibility review](packing-review-accessibility.png).
