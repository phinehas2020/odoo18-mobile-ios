# Warehouse UX refinement

Scope: native work entry, receipt detail, manufacturing detail and action forms.
Captured fresh fixture-driven simulator screenshots during this review. These are
actual SwiftUI screens with controlled sample data, not live operational records.

1. **Choose work.** The previous home implementation presented every destination as
   a separate large card. Workspace now groups navigation into Your work, Warehouse,
   Production and Other apps. Primary tasks are normal native rows, with search and
   Settings in consistent system positions. See ux-workspace.png.
2. **Understand the operation.** The fresh before-manufacturing.png capture shows one
   operation consuming most of the screen with equal emphasis on metadata and actions.
   Manufacturing now separates Work / Materials / Quality, keeps the summary compact,
   and expands an operation to reveal employee, product and timing fields.
   See warehouse-manufacturing-screen.png.
3. **Take the next action.** Production derives its main action from actual planning,
   operation and required-quality states. Pause is secondary. Completion still uses
   the existing review/confirmation flow. Nothing is automatically posted because an
   action is suggested. Receipt scanning is in the toolbar; manual entry is expandable;
   receipt review has one stable bottom action. See ux-receipt-light.png.
4. **Review before posting.** Quantity, stock, return, production and quality forms
   retain their guards and confirmations with shorter labels and native control sizing.

Accessibility review: status retains both text and symbol, not color alone. Inspected
light/dark receipt screens and manufacturing at accessibility3 text. Fixed a discovered
large-text footer overflow by moving actions into the scrollable content and stacking
controls. Large-text section navigation uses a menu rather than a cramped segmented
control. Screen captures cannot establish VoiceOver navigation or physical dexterity;
those need device interaction checks.

Validation: full iOS suite 27 tests passed. Subsequent screenshot-only tests passed after
normalizing initial scroll position. No backend changes or production transactions.
These UI changes are local and require rebuilding the phone app; not pushed in this turn.
