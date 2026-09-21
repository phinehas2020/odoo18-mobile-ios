# Warehouse workflows

## Native iPhone workflows

- Receipts, deliveries, internal transfers, and completed-transfer history.
- Barcode detection inside a target area, detected-code preview, explicit confirmation,
  persistent result, Scan next and Done. Merely detecting a code never posts a scan.
- Absolute quantities and lot/serial entry; demand-level receipt entry when move lines
  do not exist yet; one line per serial number.
- Transfer completion with explicit create-backorder or cancel-remainder decisions.
- Returns from completed transfers: review quantities, create the return, open and process it.
- Stock lookup by product/barcode, showing on-hand, reserved and available quantities per
  location/lot. Count adjustment and scrap use separate review and confirmation steps.
- Manufacturing product selection, quantity, responsible person, deadline and notes.
- Planning, component and lot information, work-order Start/Pause/Finish controls.
- Quality instructions, pass/fail, and required photo capture/selection.
- Reviewed manufacturing completion with actual production and consumption quantities,
  finished lot/serial, component lot allocation, and partial-production backorders.
- Regular users' manufacturing list follows the responsible user; Settings administrators
  retain the broader list under Odoo's company permissions.

## Behavior and boundaries

Stock-changing actions require a connection. Previously loaded receipt data remains
available offline, but cannot be used to post stale stock changes. After an uncertain
response, refresh before another attempt. Failed legacy outbox events are preserved
for review rather than repeatedly submitted.

Completion respects existing Odoo constraints and permissions. No permissions are
automatically granted. Inventory adjustments and scrap require Inventory Manager;
quality workflows require the configured Quality Operator/Manager access. A failure
never becomes success merely because an HTTP request returned 200.

Lists have bounded results: manufacturing shows up to 200 open orders; stock lookup
shows 50 matching existing stock rows. Stock counting currently operates on existing
quant rows; it is not a product/location creation interface. Serial-tracked finished
production is completed one serial at a time. Unexpected specialized Odoo wizards
remain explicit blockers rather than being silently bypassed.

## Verification

- iOS XCTest suite: 25 passing tests, including scanner gating, receipt payloads,
  backorder token continuity, cache round-trip, decoding and recovery cases.
- Fixture-driven manufacturing screen rendered in Simulator for visual inspection.
- Odoo integration suite: 34 passing post-tests across inventory, manufacturing and sync.
- Odoo integration tests use the fresh disposable `mobile_warehouse_test_20260921`
  database, isolated addon copies, no production data and no cron workers.
- Physical barcode accuracy, device camera/photo permissions and operator acceptance
  still require on-device use; simulator and API tests do not prove physical behavior.

The companion API contracts live in the inventory and manufacturing addon README files
in `/Users/phinehasadams/odoo18-mobile-api`. Changes remain uncommitted unless explicitly
published in a later task.

## Deployment

Deployed 11 tested API runtime files on 2026-09-21. Rollback manifest on the Odoo host:
`/Users/admin/odoo18-mobile-api-cleanup-backups/warehouse-workflows-20260921-150910/manifest.json`.
Odoo restarted with both local and external login HTTP 200. Public OpenAPI includes
stock, adjustment, scrap, return, completion-review and quality-photo routes.
Read-only production checks validated receipt 523, five stock rows and five
manufacturing detail responses. No production inventory transactions were executed.
The iOS changes require rebuilding/installing the app on the phone.
