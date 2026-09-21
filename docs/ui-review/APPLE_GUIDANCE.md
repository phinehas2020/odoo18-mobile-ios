# Warehouse UI review

Reviewed Apple's Human Interface Guidelines for color, accessibility, buttons,
feedback, typography, layout, lists, and progress indicators. This is a focused
review of relevant guidance, not a claim to have read every Apple UI publication.

- https://developer.apple.com/design/human-interface-guidelines/color
- https://developer.apple.com/design/human-interface-guidelines/accessibility
- https://developer.apple.com/design/human-interface-guidelines/buttons
- https://developer.apple.com/design/human-interface-guidelines/feedback
- https://developer.apple.com/design/human-interface-guidelines/typography
- https://developer.apple.com/design/human-interface-guidelines/layout
- https://developer.apple.com/design/human-interface-guidelines/lists-and-tables
- https://developer.apple.com/design/human-interface-guidelines/progress-indicators

Applied: semantic status badges with distinct symbols and text; system colors;
primary text on subtle backgrounds; 52-point action heights; secondary Pause
styling; status filtering and loaded counts; numeric receipt progress; vertically
stacked detail labels at accessibility text sizes.

Rendered and inspected actual SwiftUI badge/detail components in light, dark,
and accessibility3 text modes. These are component previews, not screenshots of
live authenticated workflows. Full VoiceOver interaction, physical-device outdoor
contrast, and the full screens at every text size remain to be audited.
