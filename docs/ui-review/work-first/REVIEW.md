# Work-first interface

This revision supersedes the earlier segmented order screen and Workspace directory.

- App opens to assigned work, with separate Work, Warehouse and More tabs and independent navigation histories.
- Existing permission-driven menus and admin assignment behavior are preserved.
- Active operation presents work center, employee, quantities, elapsed/expected time, and related controls together.
- Pause and Finish use equal-sized controls differentiated by style, not size.
- Quality checks follow the active operation; materials are expandable.
- Removed the detached production footer and the largely empty segmented layout.
- Stock count/scrap actions live in an accessible row menu instead of repeated buttons.
- No server behavior, business permissions or inventory data changed.

## Apple source reading

Read the complete extracted primary article text for these four HIG articles in this revision:

- https://developer.apple.com/design/human-interface-guidelines/design-principles
- https://developer.apple.com/design/human-interface-guidelines/designing-for-ios
- https://developer.apple.com/design/human-interface-guidelines/layout
- https://developer.apple.com/design/human-interface-guidelines/buttons

This does not claim every linked reference, image, supplementary article or every Apple design article was read.

## Verification

27 iOS tests passed. Screens are actual simulator-rendered SwiftUI views with controlled sample data, not production screenshots. Inspected Work, Warehouse, active production, and large-text production renders. Existing receipt light/dark captures remain part of the suite. Navigation uses native tab and stack controls; physical-device usability and VoiceOver interaction have not been fully audited.

App changes are local and uncommitted. Rebuild/install on the phone to use them.
