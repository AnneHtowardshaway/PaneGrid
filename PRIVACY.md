# Privacy

PaneGrid is an offline native utility. It has no account system, advertising, telemetry, analytics, network client, or remote settings service.

## Accessibility

Window management requires your explicit macOS Accessibility approval. PaneGrid reads application identifiers, window titles, positions, sizes, resize capability, and the geometry of window controls. It changes the positions and sizes of the windows you explicitly target or select.

The green-button picker uses public Accessibility hit-testing and mouse position. The global shortcut uses the system hot-key API. PaneGrid does not record keystrokes, inspect document contents, capture screenshots, or require Screen Recording or Input Monitoring for its normal operation.

## Local storage

Preferences and saved layouts are written atomically to `~/Library/Application Support/PaneGrid/configuration.json`. The directory is created with owner-only access and the configuration file with owner read/write access. A damaged or unsupported configuration is preserved before defaults are used. No local settings are copied into the source repository.

Saved layouts contain application bundle identifiers and window titles. An exported layout can therefore reveal document names. Review exports and screenshots yourself before sharing them publicly. Importing a layout does not execute code, open files, or launch its associated applications.

## Verification modes

The interface probe uses ephemeral settings and its own windows. The native probe only opens and targets the bundled `PaneGrid Practice` app. It refuses to run window-control checks without Accessibility approval. Verification reports are written only to the path requested by the person running the probe; they contain practice-window test results and window dimensions, not personal application contents.

## Removal

Quit the app, remove `/Applications/PaneGrid.app`, and remove its entry from Accessibility settings if desired. Optional launch at login is managed through macOS and can be disabled in PaneGrid or System Settings. Remove the PaneGrid Application Support directory only if you also want to delete saved layouts and preferences.
