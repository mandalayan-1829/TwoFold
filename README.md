# TwoFold

**Two Hearts. One Little Universe.**

TwoFold is a private, mobile-first web application designed exclusively for two people in a relationship to preserve shared memories, plan dates, exchange love letters and surprises, and chat in real time.

## Architecture & Stack

- **Frontend:** React, TypeScript, Vite, Custom CSS
- **Backend:** Supabase (Authentication, PostgreSQL with Row Level Security, Realtime, Private Storage)
- **Hosting:** Portable static build (Vercel Hobby as initial target)
- **Budget:** Designed for ₹0/month free-tier infrastructure

## Security Principles

- **Default-deny authorization:** Exactly two provisioned users belong to a single couple space, enforced in PostgreSQL RLS and Supabase Storage policies.
- **No public registration:** Accounts are provisioned privately through controlled setup.
- **Private storage only:** Media buckets are never public; access relies on authenticated storage policies and short-lived signed URLs.
- **Strict secret hygiene:** Never commit `.env`, `.env.local`, or Supabase `service_role` keys.

## Documentation

- [Software Requirements Specification](docs/01_SRS.md)
- [Design Specification](docs/02_Design_Specification.md)
- [Security Specification](docs/03_Security_Specification.md)
- [Technology Stack & Architecture](docs/04_Technology_Stack_and_Architecture.md)
- Supabase Setup Guide: `supabase/SETUP_GUIDE.md` *(added in Milestone 1)*

## Local Development

1. Install dependencies:

   ```bash
   npm install
   ```

2. Create `.env.local` from `.env.example` and populate your Supabase project URL and public anon key:

   ```bash
   cp .env.example .env.local
   ```

3. Start the development server:

   ```bash
   npm run dev
   ```

4. Validate linting and production build:

   ```bash
   npm run lint
   npm run build
   ```
