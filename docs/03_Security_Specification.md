# Our Little Universe --- Security Specification

**Document version:** 1.0\
**Status:** Initial security baseline\
**Date:** 20 November 2026

## 1. Security objectives

The application stores highly personal conversations, photographs,
videos, letters, date information, and potentially location data. The
default security posture is **deny access unless explicitly
authorised**.

The security design must protect: - Confidentiality of all couple
content. - Integrity of memories, messages, plans, and account
membership. - Availability within the chosen provider's free-tier
limits. - User control over media and location sharing.

## 2. Identity and authentication

-   Use managed email/password authentication.
-   Only two pre-approved user IDs may become members of the couple
    space.
-   Disable open public registration in the production application.
-   Provision the two accounts through a controlled owner/admin setup
    process initially.
-   Require strong, unique passwords.
-   Use provider-supported email verification and password recovery when
    correctly configured.
-   Never store raw passwords in the application database.
-   Use secure, provider-managed sessions and sign-out.
-   Do not implement custom password hashing or authentication.

**Important:** Authentication proves who signed in. It does not
automatically authorise access to the couple's data. Every data
operation must also check membership.

## 3. Authorisation model

### 3.1 Membership invariant

There must be exactly two active member user IDs for the single couple
space. A third user must never be able to join through a manipulated
client request.

### 3.2 Access policy

-   Unauthenticated users: no private data access.
-   Authenticated but non-member users: no couple data access.
-   Approved member A: access shared couple data.
-   Approved member B: access shared couple data.
-   Privileged service credentials: server-side only; never sent to the
    browser.

### 3.3 Enforcement

-   Enforce membership in database row-level security (RLS) policies.
-   Enforce equivalent access checks for storage objects.
-   Scope every shared record to the couple-space ID.
-   Validate sender/creator IDs against the authenticated session.
-   Do not trust a couple ID, user ID, role, file path, or timestamp
    supplied by the browser.
-   Test policies using an unauthenticated user, each approved user, and
    a third test user.

## 4. Database security

-   Enable RLS on every table exposed to the client.
-   Default to deny; add only the policies required for each feature.
-   Prevent users from changing their own role or membership status.
-   Prevent the client from adding a third member.
-   Restrict updates to permitted fields.
-   Validate data types, lengths, and required fields.
-   Use server-side functions for privileged operations.
-   Avoid exposing database administration keys in frontend bundles.

## 5. File and media security

-   Use a private storage bucket/container.
-   Restrict uploads and downloads to the two approved members.
-   Use short-lived signed URLs when a direct temporary media URL is
    needed.
-   Never make private relationship media publicly readable.
-   Enforce file-size limits and allowed MIME types.
-   Generate safe storage object names; do not trust user-provided
    paths.
-   Do not allow executable files to be uploaded.
-   Consider image metadata/EXIF stripping before sharing, especially
    GPS metadata.
-   Add video uploads only after storage limits and access policies are
    verified.
-   Deleting a memory should have a defined policy for its attached
    media.

## 6. Chat and letters

-   Only the two approved members can read shared messages and letters.
-   The sender ID must come from the authenticated session, not a
    client-supplied field.
-   Validate message length and attachment references.
-   Avoid logging message bodies or letter content in application logs.
-   Scheduled letter/surprise unlocks must be checked using trusted
    server/database time, not only browser time.
-   Message deletion/editing behaviour must be documented and consistent
    for both users.

## 7. Location privacy

Location sharing is a later-release feature and must remain disabled
until these controls exist:

-   Sharing is off by default.
-   A user explicitly starts sharing.
-   The interface clearly shows when sharing is active.
-   The user can stop sharing immediately.
-   Temporary sharing has an expiry time.
-   Show last-updated time.
-   Collect location only while the user has granted browser permission
    and sharing is active.
-   Do not claim continuous background tracking when the browser/app is
    closed.
-   Store the minimum precision and history necessary.
-   Apply automatic expiry/deletion to old location points.
-   Never expose location data through public URLs or public maps.

## 8. Frontend and application security

-   Use HTTPS in production.
-   Keep secrets in environment variables or server-side secret storage.
-   Never commit `.env` files, service-role keys, admin credentials, or
    private data.
-   Validate and sanitise user-generated content.
-   Render user text as text; avoid unsafe HTML injection.
-   Use a restrictive Content Security Policy where practical.
-   Protect privileged server actions from unauthorised calls.
-   Apply rate limits to login, invitation, and message endpoints where
    supported.
-   Avoid putting private content in analytics, crash reports, or
    third-party AI prompts.
-   Keep dependencies updated and remove unused packages.

## 9. GitHub and deployment hygiene

The public repository may contain application source code and
non-sensitive documentation only.

Never commit: - `.env` or `.env.local`. - Database passwords or
service-role keys. - Authentication tokens. - Private photographs,
videos, letters, or chat exports. - Real location coordinates. -
Production database dumps.

Include `.env.example` with placeholder names only. Configure repository
secret scanning if available.

## 10. Backup, deletion, and recovery

-   Provide a way to export important memories in a future release.
-   Define whether deleting an item removes its media object as well.
-   Provide an account/data deletion procedure.
-   Do not promise backups on a free tier unless backups are actually
    configured and tested.
-   Keep a manual export of non-sensitive schema and setup
    documentation.

## 11. Security test checklist

Before deployment, verify:

1.  Signed-out visitor cannot read any private record.
2.  A third authenticated test user cannot read couple data.
3.  A third user cannot insert themselves into membership.
4.  User A cannot impersonate User B by changing request payloads.
5.  A non-member cannot read a private media object.
6.  Private media URLs are not permanent public links.
7.  A user cannot alter a scheduled letter's unlock time to bypass
    restrictions.
8.  A user cannot access location data when sharing is off or expired.
9.  No secret is present in the built frontend bundle or Git history.
10. Deleting a record handles its associated files as specified.

## 12. Incident response

If a credential or secret is exposed: 1. Revoke/rotate it immediately.
2. Review provider logs and recent access where available. 3. Remove the
secret from the active codebase and Git history if committed. 4.
Re-deploy with rotated credentials. 5. Inform the other user if their
private data may have been exposed.
