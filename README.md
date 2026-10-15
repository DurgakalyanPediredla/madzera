# Madzera

Madzera is an early-stage, privacy-first operational workflow and customer communication platform being developed for UK customs intermediaries.

The platform aims to help customs brokers and freight operations teams manage customer enquiries, internal cases, employee ownership, audit trails and supervisory workflows without replacing their existing customs declaration systems.

## Problem

Customs intermediaries may manage enquiries and operational work across email, telephone, spreadsheets and disconnected documents.

This can make it difficult to track ownership, avoid duplicated work, monitor outstanding enquiries and reconstruct operational decisions.

Madzera is exploring a structured workflow layer that improves operational visibility while minimising unnecessary duplication of customer and shipment information.

## Product Direction

Planned capabilities include:

- Multi-tenant organisation and employee management
- Customer enquiry and internal case management
- Team routing and employee assignment
- Exclusive case-working sessions
- Chronological audit history
- Internal and customer-visible communications
- Document references and controlled attachments
- Operational tasks and supervisory review
- Independent four-eyes approval
- Case metrics and operational reporting
- Future authorised integrations and AI-assisted communication

These are product objectives, not a claim that every feature is operational.

## Current Implementation

As of 15 October 2026, Madzera has a PostgreSQL and Supabase development backend with 32 versioned SQL migrations.

Implemented and tested components include:

- A 15-table relational data model
- Organisation, employee, team, customer and case structures
- Supabase Auth identity mapping
- Selected organisation-level Row Level Security policies
- Database constraints supporting tenant integrity
- Case events and update audit triggers
- Controlled employee case creation through a database function
- Case queue retrieval through a database function
- Exclusive case-lock acquisition and release
- Case-session opening, renewal and closing functions
- Lock-token-protected case detail retrieval
- Restricted direct authenticated access to the cases table

Selected workflows have been tested using synthetic data, SQL role simulation and authenticated Supabase REST requests.

These tests do not establish complete security coverage or production readiness.

## Case Access Model

The intended employee workflow is:

1. Authenticate as an active employee.
2. Retrieve an authorised case queue.
3. Open a case-working session.
4. Acquire an exclusive, time-limited case lock.
5. Retrieve case details using the valid lock token.
6. Perform authorised workflow actions.
7. Record changes and audit events.
8. Release the lock when the session closes.

The current backend implements and tests selected parts of this workflow.

Controlled employee case updates requiring an active lock remain under development. Direct authenticated case-table SELECT, INSERT, UPDATE and DELETE privileges are restricted in the hosted development project.

## Security Architecture

Security controls under development include:

- Authentication through Supabase Auth
- Active employee identity verification
- Organisation-level tenant isolation
- Least-privilege database permissions
- Security-definer functions for controlled workflows
- Exclusive, expiring case locks
- Token-validated case detail retrieval
- Employee-attributed audit events
- Protected case identifiers and organisation ownership

Security limitations:

- Complete tenant isolation across every table and function has not been established.
- Team-level and management permissions require further testing.
- The case-update audit trigger does not currently enforce an active case lock.
- Four-eyes approval is not yet enforced as a complete workflow.
- Storage, attachment access and customer-facing authorisation remain incomplete.
- No independent penetration test or production security assessment has been completed.

No real customer documents or customs declaration data should be used during this prototype stage.

## Technology

- PostgreSQL
- Supabase Auth and database APIs
- Supabase CLI
- Docker for local development
- Next.js frontend project
- Git and GitHub for version control

## Repository Structure

- `database/schema.sql` — original relational schema
- `database/seed_demo.sql` — synthetic demonstration data
- `database/migrations/` — incremental SQL migrations
- `database/tests/` — SQL tests and documented evidence
- `web/` — Next.js frontend project
- `README.md` — project overview and implementation status

The original schema file alone should not be assumed to reproduce the latest database state. Incremental migrations are also required.

## Testing and Evidence

Testing currently includes:

- Manual PostgreSQL security assertions
- SQL-based simulated authenticated sessions
- Local Supabase development testing
- Selected real authenticated REST API tests against the hosted development project
- Case creation, queue access, session locking and secure detail retrieval
- Direct case-table permission checks

Historical tests may describe privileges that were intentionally changed by later migrations.

See:

- `database/tests/TEST_MATRIX.md`
- `database/tests/TEST_RESULTS.md`

Automated continuous-integration regression testing is not yet established.

## Development Priorities

1. Consolidate test evidence and regression coverage.
2. Implement controlled, lock-validated case updates.
3. Complete workflow authorisation and assignment rules.
4. Implement independent supervisory and four-eyes approval.
5. Develop the employee operations interface.
6. Implement secure attachment and document handling.
7. Develop customer-safe status and communication interfaces.
8. Add operational reporting and analytics.
9. Evaluate authorised integrations and AI-assisted workflows.
10. Conduct broader security and production-readiness testing.

## Project Status

Early-stage development prototype undergoing backend workflow validation, security hardening and practitioner research.

Madzera is not yet production-ready.
