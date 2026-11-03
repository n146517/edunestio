# EduNestIO — UI Design System

Original branding (not copied from any reference assets). Card-based, clean,
responsive, accessible.

## Brand
- **Name**: EduNestIO.
- **Primary**: deep green `#0f5132` (navigation, primary CTA).
- **Accent / header**: `#14532d`.
- **Danger**: `#b3261e`. **Info**: `#1f6feb`. **Success**: `#2e7d4f`.
- **Surfaces**: white cards `#ffffff` on pale background `#eef2f0`; borders `#e0e4e2`.
- **Text**: `#1f2a24` on light; muted `#6b7772`.

## Typography & spacing
- System font stack (Segoe UI / -apple-system / Roboto …).
- Headings: h1 1.5rem. Body ~0.9–0.95rem. Rounded corners 6–10px. Card padding ~1.25rem.

## Components (implemented)
- **App shell** (`layout/shell`): top bar with brand + user menu (username, full name,
  tenant, sign out); left sidebar navigation with active state and "soon" badges for
  planned modules; responsive content area.
- **Login**: centered card, brand mark, reactive form, inline validation.
- **Dashboard**: status card (loading/success/error states) + access summary.
- **Students**: toolbar search, table grid, status badges, admit form (gated by
  `student.create`), deactivate action with confirm (gated by `student.delete`),
  pagination, and loading/empty/error states.
- **Toasts** (`core/NotificationService`): success/error/info, auto-dismiss.

## States & accessibility
- Every data view implements loading, empty, error, and success states; permission
  gating hides actions the user cannot perform (server still enforces).
- Destructive actions use a confirmation dialog.
- Reactive forms with accessible `<label>`s and visible validation messages.
- Keyboard-usable controls and readable contrast on primary/background pairs.

## Assets (original SVG, under `frontend/school-web/public/`)
Branding is delivered as original, hand-authored SVGs (no third-party/stock imagery):
- `logo.svg` — full word-mark (nest-cradled book + "EduNestIO"); used on the login screen.
- `logo-mark.svg` — square app mark; used in the shell header.
- `favicon.svg` — browser tab icon (referenced in `index.html`, with `favicon.ico` fallback).
- `icons/students.svg`, `icons/academic.svg`, `icons/attendance.svg`, `icons/fees.svg` —
  module-card icons used on the dashboard's card-based module discovery grid.

The dashboard renders a responsive **module card grid** (inspired by the brief's
screenshots): white rounded cards, green accent icons, hover elevation, and a "soon"
badge on planned modules. New modules add an icon SVG + a card entry.

## Extension rules
- New module pages reuse the shell, toast service, table/grid and form patterns, and
  the `ApiResponse`-aware HTTP services. Keep tokens centralized; avoid per-page color
  drift. Replace a nav placeholder with the real route when a module ships.
