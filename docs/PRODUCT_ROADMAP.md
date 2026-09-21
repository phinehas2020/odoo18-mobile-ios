# Mobile Odoo: simple daily work

## First increment

Home uses large labeled app cards, a short explanation for each native workflow,
app search, refresh, and a direct Settings shortcut. Sales and Warehouse offer
search and refresh. Request failures are visible and retain previously loaded
records. Warehouse explicitly labels its existing server filter: ready transfers
assigned to the current user. Odoo web sessions are recreated on retry.

## Build out in workflow order

1. Receipts: incoming deliveries, quantity entry, lots, partial receipts and backorders.
2. Manufacturing orders: components, availability, production quantities and tracking.
3. Work orders: work centers, start/pause/finish, instructions and quality checks.
4. Warehouse transfers: scanning, offline replay and duplicate prevention.
5. Sales and purchasing follow the warehouse floor workflows.

Each increment needs a large primary action, plain-language state, a recovery
path, and verification against a disposable Odoo database before production use.
Do not equate a web link with complete native support or a build with live QA.

## Remaining first-pass limitations

Search filters records already returned by the API; it is not server-wide search.
Authenticated screens and mutations need a dedicated test account/database for
end-to-end validation. Detail screens, offline synchronization, and accounting
workflows have not been comprehensively audited in this increment.

## Warehouse increment (2026-09-21)

- Native manufacturing list and detail use the existing manufacturing API.
- Work orders are reached through their manufacturing order; they are not a global work-center queue yet.
- Start, pause and finish use existing workflow endpoints. Finish has a review confirmation.
- Actions are online-only and blocked after an uncertain response until a successful refresh.
- Lists show up to 200 open MOs, with a due/overdue filter and local search.
- Receipts loads open transfers across assignees and filters by exact `picking_type_code == incoming`.
- The companion API change adds `picking_type_code` to transfer responses. Deploy/update
  `mobile_api_inventory` before using receipts against a server without this field.
  A nonempty old response shows an update-required message instead of misclassifying transfers.
- Transfer completion now checks the response and reloads the record; it only reports
  completion when the returned state is done. Partial receipts may still require Odoo.
- Full MO completion is deliberately not exposed yet: the existing endpoint assumes
  full production and consumption. Quantity, lot and quality review must come first.
- Receipt-type API patch deployed to the Odoo Mac Mini on 2026-09-21. Odoo restarted successfully; local and external login returned HTTP 200, and the public OpenAPI schema includes `picking_type_code` in both picking response models. Phone receipt-list verification remains pending. No inventory transactions were performed.

## Warehouse implementation update

The expanded workflow implementation and verification boundaries are documented in
[WAREHOUSE_WORKFLOWS.md](WAREHOUSE_WORKFLOWS.md). This supersedes the initial
read-only manufacturing and deferred-completion limitations above.
