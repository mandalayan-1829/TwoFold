# Our Little Universe --- Technology Stack & Architecture

**Document version:** 1.0\
**Status:** Initial architecture baseline\
**Date:** 20 November 2026\
**Budget target:** ₹0/month initially

## 1. Architecture decision

Use a **single Supabase backend** for the initial build rather than
mixing Firebase and Supabase. This keeps authentication, database,
real-time subscriptions, and private object storage under one
access-control model.

Use Google AI Studio as the AI-assisted development environment. AI
Studio generates and edits code; it is not the production backend or
database.

Before implementation, check current free-tier eligibility, quotas,
inactivity/pause rules, and email-delivery restrictions. Do not enable a
paid plan or attach billing details just to make a feature work.

## 2. Recommended stack

  -----------------------------------------------------------------------
  Layer                   Technology              Responsibility
  ----------------------- ----------------------- -----------------------
  AI-assisted development Google AI Studio Build  Generate and iterate on
                          mode                    the application

  Frontend                React + TypeScript      UI and client-side
                                                  application

  Build tool              Vite                    Local development and
                                                  production build

  Styling                 CSS modules or          Responsive visual
                          organised global CSS    system

  Backend platform        Supabase                Managed backend
                                                  services

  Authentication          Supabase Auth           Email/password identity

  Database                Supabase PostgreSQL     Users' shared
                                                  application data

  Authorisation           PostgreSQL RLS          Enforce two-member
                                                  privacy

  Realtime                Supabase Realtime       Chat and shared updates

  Object storage          Supabase Storage        Private images and
                                                  later media

  Maps                    Leaflet + OpenStreetMap Display saved date
                          tiles                   locations

  Calendar                FullCalendar or a       Shared date planner
                          lightweight custom      
                          calendar                

  PWA                     Web App Manifest +      Installable app
                          Service Worker          experience

  Hosting                 Vercel Hobby or another Serve the frontend
                          free static host        

  Version control         Git + GitHub            Source control and
                                                  portfolio
  -----------------------------------------------------------------------

### Why this stack?

-   One backend platform reduces integration complexity.
-   PostgreSQL is a good fit for relational data such as members,
    memories, dates, and messages.
-   RLS provides database-enforced privacy.
-   Supabase Realtime supports live chat updates.
-   Private Storage can keep uploaded media behind access policies.
-   React + TypeScript is suitable for an AI-assisted web application.
-   PWA support can be added without building a separate native app.

## 3. Free-tier constraints and cost controls

The target is ₹0, but free tiers are quotas, not unlimited services.

-   Start with text-only chat and memory records.
-   Add image uploads after private storage policies are tested.
-   Delay video and voice uploads; they use storage and bandwidth
    quickly.
-   Compress images in the browser before upload.
-   Set maximum file sizes and accepted file types.
-   Avoid paid maps, paid AI APIs, paid email services, and custom
    domains.
-   Use a free hosting subdomain.
-   Check the current provider dashboard for quota usage.
-   Do not enter payment details or upgrade plans to bypass a limit.
-   If a free-tier limitation blocks a feature, defer that feature
    rather than silently introducing a cost.

**Email note:** Supabase's built-in email service may have low sending
limits or recipient restrictions. For a two-account first release,
provision both accounts through the Supabase dashboard and test the
actual sign-in/recovery flow. Do not assume production-grade email
delivery is unlimited or included.

**Storage note:** Confirm the current Supabase free storage quota and
project policies before uploading personal media. Keep a local copy of
important originals. A free service is not a substitute for a backup.

## 4. High-level architecture

``` text
      Phone / Laptop Browser
                |
         React + TypeScript
                |
        HTTPS deployed frontend
                |
       Supabase client (public key)
                |
   ---------------------------------
   |              |                |
 Supabase Auth  PostgreSQL       Realtime
   |              |                |
 Email login   RLS-protected     Chat updates
 Sessions      couple data       Shared changes
                  |
             Supabase Storage
                  |
          Private media objects
```

The browser may contain the Supabase project URL and public
anon/publishable key. It must never contain the service-role key or
database password. RLS and storage policies must be correct before the
application is considered private.

## 5. Data model overview

Suggested relational structure:

``` text
profiles
  id (auth user id)
  display_name
  avatar_path
  created_at

couples
  id
  anniversary_date
  created_at

couple_members
  couple_id
  user_id
  role
  joined_at

memories
  id
  couple_id
  created_by
  title
  description
  event_date
  category
  created_at
  updated_at

media_objects
  id
  couple_id
  uploaded_by
  storage_path
  mime_type
  size_bytes
  created_at

messages
  id
  couple_id
  sender_id
  body
  created_at

date_plans
  id
  couple_id
  created_by
  title
  starts_at
  ends_at
  location_text
  notes
  budget
  status

letters
  id
  couple_id
  sender_id
  title
  body
  unlock_at
  created_at

surprises
  id
  couple_id
  created_by
  title
  content
  reveal_at
  created_at
```

Add location tables only in the location-sharing phase, after expiry,
opt-in, and RLS rules are designed.

## 6. Suggested application folder structure

``` text
our-little-universe/
├── public/
│   ├── icons/
│   ├── manifest.webmanifest
│   └── offline.html
├── src/
│   ├── app/
│   ├── components/
│   │   ├── layout/
│   │   ├── ui/
│   │   └── shared/
│   ├── features/
│   │   ├── auth/
│   │   ├── dashboard/
│   │   ├── memories/
│   │   ├── chat/
│   │   ├── letters/
│   │   ├── planner/
│   │   └── surprises/
│   ├── hooks/
│   ├── lib/
│   │   └── supabase/
│   ├── styles/
│   ├── types/
│   └── main.tsx
├── supabase/
│   ├── migrations/
│   └── seed.sql
├── docs/
├── .env.example
├── .gitignore
├── package.json
└── README.md
```

## 7. Environment variables

Use placeholders in `.env.example`:

``` env
VITE_SUPABASE_URL=
VITE_SUPABASE_ANON_KEY=
```

The real `.env.local` file must be ignored by Git. Never place a
service-role key in a `VITE_` variable or any browser-accessible file.

## 8. Development phases

### Phase 0 --- project foundation

-   Create GitHub repository.
-   Create React + TypeScript project.
-   Configure formatting and folder structure.
-   Create Supabase project.
-   Configure environment variables.
-   Establish database schema and RLS before adding private data.

### Phase 1 --- secure MVP foundation

-   Provision the two accounts.
-   Create couple space and membership records.
-   Test that a third account is rejected.
-   Implement login, logout, and protected routes.
-   Build responsive navigation and dashboard shell.

### Phase 2 --- memories and planner

-   Implement memory CRUD.
-   Implement date-plan CRUD.
-   Link completed date plans to memories.
-   Add private image uploads only after storage RLS tests pass.

### Phase 3 --- communication and expression

-   Implement real-time text chat.
-   Implement letters.
-   Add surprise creation and reveal.
-   Enforce scheduled unlocks using trusted time.

### Phase 4 --- PWA and polish

-   Add manifest, icons, service worker, and offline fallback.
-   Test install on Android and desktop browsers.
-   Ensure private content is not cached offline.
-   Test accessibility and mobile responsiveness.

### Phase 5 --- later features

-   Video and voice notes.
-   Location sharing with opt-in and expiry.
-   Couple games.
-   Bucket list and annual recap.

## 9. Architecture rules

1.  The UI must not be the security boundary.
2.  Every shared table must include a couple-space reference.
3.  RLS must protect every client-accessible table.
4.  Storage buckets must be private.
5.  Service-role credentials must remain server-side.
6.  Do not build background location tracking into a browser PWA.
7.  Do not add an AI feature that sends private content to a model
    without explicit consent.
8.  Keep the application usable within free-tier quotas.
9.  Commit schema changes as migrations.
10. Test security with a third, unauthorised account before launch.

## 10. Initial implementation decision

Start with **React + TypeScript + Vite + Supabase** in Google AI Studio.
Build the secure sign-in and two-member access model first. Do not start
with animations, games, video uploads, or location tracking. The first
milestone is a private, working dashboard that only the two intended
accounts can access.
