# Our Little Universe --- Design Specification

**Document version:** 1.0\
**Status:** Initial design baseline\
**Date:** 20 November 2026

## 1. Design direction

The product should feel like a warm, intimate digital scrapbook rather
than a generic social network. The visual language should be calm,
personal, elegant, and readable.

### Visual identity

-   **Primary mood:** warm, intimate, nostalgic, modern.
-   **Suggested palette:** deep cherry/burgundy, dusty rose, warm ivory,
    muted blush, soft charcoal.
-   **Typography:** elegant serif for large headings; clean sans-serif
    for body text.
-   **Surface style:** rounded cards, subtle borders, restrained
    shadows, generous spacing.
-   **Motion:** gentle transitions and small reveal animations; avoid
    excessive animation.
-   **Imagery:** polaroid-inspired memory cards, album covers, and date
    photographs.

The interface must remain readable and usable if animations are disabled
or the user prefers reduced motion.

## 2. Information architecture

Primary navigation:

1.  **Home** --- shared dashboard.
2.  **Memories** --- timeline, albums, categories, and memory detail.
3.  **Chat** --- private conversation.
4.  **Letters** --- received, sent, drafts, and time-locked letters.
5.  **Date Planner** --- shared calendar and upcoming plans.
6.  **Surprises** --- create and open surprises.
7.  **Our Future** --- shared bucket list (later release).
8.  **Settings** --- profiles, privacy, notifications, and sign out.

On mobile, use a compact bottom navigation for the most-used sections
(Home, Memories, Chat, Planner) and a secondary menu for the rest. On
desktop, use a left sidebar or top navigation.

## 3. Screen specifications

### 3.1 Landing and authentication

-   A minimal welcome screen with product name and short tagline.
-   Email and password fields.
-   Sign-in and password recovery.
-   No public "create account" link in production.
-   Optional invitation/setup screen available only during controlled
    onboarding.
-   Clear loading, invalid-credentials, and network-error states.

### 3.2 Home dashboard

-   Greeting using the user's display name.
-   Relationship anniversary counter.
-   Upcoming date card.
-   Recent memory cards.
-   Unread chat indicator.
-   Pending surprise card.
-   "On This Day" memory module when historical data exists.
-   Quick actions: Add Memory, Plan a Date, Write a Letter.

### 3.3 Memory Vault

-   Timeline and grid views.
-   Filters for category and date.
-   Memory card includes cover image (if available), title, event date,
    and category.
-   Memory detail includes full description, media gallery, location
    text, and creator.
-   Add/edit form with validation.
-   Empty state encourages adding the first memory.
-   Media should load progressively and support retry on failed upload.

### 3.4 Chat

-   Clear sender/receiver message bubbles.
-   Timestamps and date separators.
-   Text composer with send button.
-   Attachment control can be hidden until secure media upload is
    implemented.
-   Show connection/loading/error states.
-   Do not expose online status or read receipts until their privacy
    implications are designed.

### 3.5 Letters

-   Visual letter/envelope cards.
-   Tabs for received, sent, and drafts.
-   Compose form with title and body.
-   Optional unlock date clearly shown to sender.
-   Locked letter screen explains when it will become available.
-   Do not rely on the client clock alone to enforce unlock time;
    enforce it in trusted backend logic or database policy.

### 3.6 Surprise Room

-   Surprise cards with title, sender, and availability.
-   A reveal interaction such as opening an envelope or unwrapping a
    gift.
-   Support text and image surprises first.
-   Scheduled reveals must be enforced by backend time checks.
-   Respect reduced-motion settings.

### 3.7 Date Planner

-   Month/list views.
-   Shared events with title, date/time, place text, notes, and optional
    budget.
-   Status: proposed, planned, completed, cancelled.
-   Both users can propose and update events.
-   Completed plans offer "Create memory".
-   Calendar should be usable on narrow screens; list view is the mobile
    fallback.

### 3.8 Settings

-   Display name and avatar.
-   Anniversary date and shared-space details.
-   Notification preferences.
-   Location-sharing controls when feature is released.
-   Sign out.
-   Account/data export and deletion guidance.

## 4. Responsive behaviour

### Mobile

-   Design from a 360px-wide viewport upward.
-   Single-column content.
-   Large touch targets (aim for at least 44px).
-   Bottom navigation for primary destinations.
-   Forms use full-width controls.
-   Media grid adapts to screen width.

### Tablet

-   Two-column card layouts where space allows.
-   Persistent navigation can be used.

### Desktop

-   Sidebar plus main content.
-   Wider memory gallery and calendar.
-   Chat may use a conversation panel and details panel.

## 5. Interaction and feedback

Every asynchronous action must have: - Loading state. - Success
feedback. - Recoverable error state. - Disabled state while submitting
to prevent duplicate actions.

Destructive actions require confirmation. Deleting a memory or message
should clearly explain whether the deletion affects both users.

## 6. PWA design requirements

-   Web app manifest with name, short name, icons, theme colour, and
    standalone display mode.
-   Service worker for app shell caching and safe static asset caching.
-   HTTPS deployment.
-   Install prompt/instructions where supported.
-   Offline fallback page.
-   Do not cache private chat, letters, location, or personal media in a
    shared/offline cache by default.
-   Push notifications are optional and must be permission-based.

## 7. Design tokens (initial proposal)

``` css
:root {
  --color-wine: #5A1834;
  --color-cherry: #7A2446;
  --color-rose: #D9A0AE;
  --color-blush: #F3DDE2;
  --color-ivory: #FFF9F3;
  --color-paper: #F7EFE8;
  --color-ink: #292326;
  --color-muted: #766B70;
  --radius-card: 18px;
  --radius-control: 12px;
  --shadow-soft: 0 8px 28px rgba(50, 20, 35, 0.08);
}
```

These are starting values, not a rigid requirement. Check contrast
before finalising.

## 8. Design acceptance checklist

-   The interface feels cohesive across all main screens.
-   Mobile navigation is usable with one hand.
-   Text contrast and form labels are accessible.
-   Loading, empty, error, and success states exist.
-   Animations are subtle and respect reduced-motion settings.
-   Private content is not included in service-worker caches.
