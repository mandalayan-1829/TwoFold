# Our Little Universe --- Software Requirements Specification (SRS)

**Project name:** Our Little Universe\
**Document version:** 1.0\
**Status:** Initial baseline\
**Date:** 20 November 2026\
**Primary users:** Two invited partners only

## 1. Purpose

Our Little Universe is a private, mobile-first web application for two
people to preserve shared memories, communicate, plan dates, exchange
letters and surprises, and optionally share their locations. It should
feel like a personal digital scrapbook combined with a small private
social space.

The project must be developed and operated on a **₹0 budget initially**.
All core features must work without requiring a paid subscription,
custom domain, or paid API. Free-tier quotas and provider policies may
change, so usage must be monitored.

## 2. Product goals

1.  Provide one private space shared by exactly two authorised accounts.
2.  Preserve relationship memories, photos, videos, letters, and plans.
3.  Support near-real-time private messaging.
4.  Make adding a memory from a date plan simple.
5.  Offer thoughtful surprises and anniversary/time-capsule features.
6.  Work well on phones and laptops, with optional PWA installation.
7.  Protect personal content through server-enforced access controls.

## 3. Users and roles

There are exactly two human users in the initial product.

-   **Owner:** The first account; can complete initial setup and
    invite/link the second account.
-   **Partner:** The second and final account.
-   **No public users:** There is no public directory, public profile,
    public feed, or open registration.

Both users can create, view, edit, and delete shared memories, messages,
date plans, letters, and shared lists, subject to the rules for each
feature. The application must reject a third member even if someone
obtains the website URL or invitation link.

For the first release, the safest onboarding approach is to provision
the two accounts manually in the backend dashboard. A one-time
invitation flow can be added after the core access-control rules have
been tested.

## 4. Scope

### 4.1 MVP --- required for first usable release

-   Responsive landing/login experience.
-   Email-and-password authentication.
-   Private couple-space setup for exactly two user IDs.
-   Dashboard with anniversary/date countdown and recent memories.
-   Memory Vault with text entries, dates, categories, captions, and
    image attachments.
-   Shared date planner/calendar with create, edit, and completion
    status.
-   Love Letters with private shared access and optional scheduled
    unlock date.
-   Surprise Room with manually created messages, letters, and reveal
    experiences.
-   Basic real-time text chat.
-   PWA manifest and installable experience.
-   Sign out, account/session handling, and basic privacy settings.

### 4.2 Later releases

-   Video and voice-note uploads.
-   Reactions, message replies, typing indicator, and read receipts.
-   Map of saved date locations.
-   Explicit, temporary live-location sharing.
-   Couple games and quizzes.
-   Shared bucket list.
-   "On This Day" memories.
-   Annual relationship recap.
-   Export/download of personal memories.

### 4.3 Out of scope for initial release

-   Public registration or multiple couples.
-   Public sharing links for private memories.
-   Payments, subscriptions, advertisements, or paid AI features.
-   Background location tracking when the app is closed.
-   Native iOS/Android applications.
-   End-to-end encrypted messaging in the MVP.
-   AI analysis of private messages, photos, or relationship data.

## 5. Functional requirements

  -----------------------------------------------------------------------
  ID                      Requirement             Priority
  ----------------------- ----------------------- -----------------------
  FR-01                   Users can sign in using Must
                          their provisioned email 
                          and password.           

  FR-02                   Unauthenticated         Must
                          visitors cannot access  
                          private application     
                          routes or data.         

  FR-03                   Only the two approved   Must
                          user IDs can access the 
                          couple space.           

  FR-04                   The dashboard displays  Must
                          anniversary             
                          information, upcoming   
                          plans, and recent       
                          memories.               

  FR-05                   Either partner can      Must
                          create, view, edit, and 
                          delete a memory.        

  FR-06                   Memories support title, Must
                          description, date,      
                          category, and optional  
                          media.                  

  FR-07                   Either partner can      Must
                          create and update       
                          shared date plans.      

  FR-08                   Completed date plans    Should
                          can be converted into   
                          memory entries.         

  FR-09                   Users can write and     Must
                          read shared love        
                          letters.                

  FR-10                   A letter can have an    Should
                          optional future unlock  
                          date.                   

  FR-11                   Users can create a      Should
                          surprise with a title,  
                          message, and reveal     
                          time or reveal          
                          interaction.            

  FR-12                   Partners can exchange   Must
                          text messages and see   
                          new messages without    
                          manually refreshing.    

  FR-13                   Users can sign out and  Must
                          recover access using    
                          the configured account  
                          recovery process.       

  FR-14                   The application can be  Should
                          installed as a PWA on   
                          supported devices.      

  FR-15                   Users can opt in to     Later
                          sharing their current   
                          location and stop       
                          sharing at any time.    

  FR-16                   Location records show   Later
                          when they were last     
                          updated.                

  FR-17                   Users can delete their  Later
                          own location-sharing    
                          session and associated  
                          records.                
  -----------------------------------------------------------------------

## 6. Core user journeys

### 6.1 First-time setup

1.  Owner signs in to the provisioned account.
2.  Owner completes the private space details, including display names
    and anniversary date.
3.  The second account is linked through a controlled setup process.
4.  The application verifies that exactly two approved user IDs are
    members.
5.  Both users land on the shared dashboard.

### 6.2 Save a memory

1.  User opens Memory Vault and selects "Add memory".
2.  User enters title, date, category, description, and optional media.
3.  The application validates the input and uploads media to private
    storage if present.
4.  The memory is saved against the couple-space ID.
5.  Both users can see the new memory.

### 6.3 Plan and complete a date

1.  Either user creates a date plan with title, date/time, optional
    place, budget, and notes.
2.  Both users see it in the shared calendar.
3.  After the date, either user marks it completed.
4.  User can create a linked memory from the plan.

### 6.4 Send a message

1.  User opens the private chat.
2.  User sends a text message.
3.  The message is stored with sender ID and timestamp.
4.  The other user receives the update through the real-time
    subscription.

## 7. Data requirements

Initial entities:

-   **profiles:** user ID, display name, avatar reference, created
    timestamp.
-   **couples:** couple ID, anniversary date, display preferences,
    created timestamp.
-   **couple_members:** couple ID, user ID, role, membership status.
-   **memories:** ID, couple ID, creator ID, title, description, event
    date, category, created/updated timestamps.
-   **media_objects:** ID, couple ID, memory/message reference, storage
    path, media type, file size, metadata.
-   **messages:** ID, couple ID, sender ID, body, created timestamp,
    optional attachment reference.
-   **date_plans:** ID, couple ID, creator ID, title, start/end time,
    location text, notes, budget, status.
-   **letters:** ID, couple ID, sender ID, title, body, created
    timestamp, optional unlock timestamp.
-   **surprises:** ID, couple ID, creator ID, title, content, reveal
    timestamp, status.
-   **location_shares:** ID, couple ID, user ID, sharing status, last
    updated timestamp, expiry timestamp.
-   **location_points:** ID, couple ID, user ID, coordinates, recorded
    timestamp, expiry timestamp.

Location entities are not part of the MVP and must not be created until
the location privacy rules are implemented.

## 8. Non-functional requirements

-   **Privacy:** All personal content is private to the two approved
    users.
-   **Authorisation:** Access control must be enforced by
    database/storage policies, not just frontend checks.
-   **Usability:** Core screens must work on small mobile screens and
    desktop.
-   **Accessibility:** Controls have labels, visible focus states,
    readable contrast, and keyboard support.
-   **Performance:** Common screens should load quickly on ordinary
    mobile connections; large media should be lazy-loaded.
-   **Reliability:** Failed uploads or saves should show a clear error
    and allow retry.
-   **Maintainability:** Components, data access, and feature modules
    should be separated.
-   **Portability:** Use standard web technologies and keep project
    configuration in Git.
-   **Cost:** The initial deployment must stay within free-tier quotas
    and must not silently enable paid services.

## 9. Acceptance criteria for MVP

The MVP is accepted when:

1.  The two intended accounts can sign in and sign out.
2.  A third account cannot join or read any private data.
3.  Both users can create and view the same memory.
4.  Both users can create and see shared date plans.
5.  Both users can create and read letters.
6.  Both users can exchange text messages with live updates.
7.  Private records remain inaccessible when signed out.
8.  The site is responsive on phone and desktop.
9.  The PWA can be installed on at least one supported mobile browser.
10. No secret keys or private user data are committed to the public Git
    repository.

## 10. Risks and constraints

-   Free-tier quotas, inactivity policies, and email-delivery limits can
    change.
-   Video files consume storage and bandwidth quickly; video upload
    should be delayed until storage limits are understood.
-   Browser push notifications and PWA behaviour vary by platform.
-   A browser cannot guarantee continuous background location tracking
    when closed.
-   A two-person product still needs careful authorisation; a hidden URL
    is not security.
-   Email verification and password reset may require configuring a
    custom SMTP provider depending on the backend provider's current
    free-tier policy.
