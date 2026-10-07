# Madzera

Madzera is an early-stage operational workflow and customer communication platform being designed for customs intermediaries.

The project is exploring how customs brokers and freight/customs operations teams can manage customer enquiries, operational cases, team ownership, audit history and supervisory review through a structured workflow rather than relying primarily on fragmented email, telephone and spreadsheet processes.

## Problem Being Explored

Early practitioner research with UK customs and freight intermediaries has identified workflows where customer enquiries and operational work may be managed across email, telephone, spreadsheets and documents.

This can create operational challenges including:

- limited visibility of ongoing work;
- manual coordination between employees;
- potential duplication of work;
- fragmented customer communication;
- difficulty reconstructing a clear operational history; and
- limited ability for customers to obtain structured status updates without contacting staff.

Madzera is being developed as a workflow and intelligence layer intended to complement, rather than replace, existing customs and operational systems.

## Product Direction

The proposed platform combines:

- organisation and team-based case management;
- controlled case ownership and routing;
- operational task management;
- chronological audit events;
- internal and customer-visible updates;
- document references and attachments;
- external system references;
- supervisory and four-eyes review workflows;
- customer conversation management; and
- future API and AI-assisted customer communication.

The architecture is being designed so that operational references can be linked to cases without requiring Madzera to duplicate entire customs declaration or shipment datasets.

## Current Development Status

The project is currently at database-backed workflow validation stage.

Completed:

- relational data model / ERD;
- PostgreSQL schema implementation;
- 15-table relational architecture;
- organisation, user and team model;
- customer and case model;
- case ownership and routing model;
- case event / audit history;
- internal versus customer-visible comments;
- attachment metadata model;
- external reference model;
- operational task model;
- four-eyes review model;
- conversation and message model; and
- synthetic end-to-end workflow validation.

Not yet implemented:

- production authentication;
- Row Level Security policies;
- backend application/API;
- internal operations portal;
- customer-facing chatbot;
- secure production document upload;
- live customs-system integrations; and
- production AI functionality.

## Synthetic Workflow Validation

A fictional customs intermediary environment has been created to test the relational model.

The demonstration scenario covers:

1. customer enquiry received through a web conversation;
2. declaration reference associated with the customer;
3. enquiry escalated into an operational case;
4. case routed to Customs Operations;
5. employee takes ownership;
6. audit event records the ownership change;
7. missing commercial invoice identified;
8. internal and customer-visible information separated;
9. customer document represented against the same case;
10. case submitted for independent four-eyes review;
11. second employee approves the review;
12. case resolved; and
13. customer-safe status retrieved from the same case record.

The scenario currently validates the data model and workflow manually through PostgreSQL. It does not represent a completed production application.

## Database

The `/database` directory contains:

- `schema.sql` — reproducible PostgreSQL database structure.
- `seed_demo.sql` — synthetic demonstration data and workflow used for development validation.

All demonstration organisations, employees, customers, email addresses, declaration references and documents are fictional.

## Architecture Direction

The intended architecture is:

Customer / Employee Interface  
↓  
Madzera Application & API Layer  
↓  
Authentication + Authorisation  
↓  
Workflow / Audit / Review Logic  
↓  
PostgreSQL  
↕  
Authorised external-system integrations

Future customer-facing AI functionality is intended to retrieve only authorised customer-safe information rather than expose unrestricted internal case information.

## Security Direction

Row Level Security has been enabled at database level.

Production RLS policies, authenticated user mapping, tenant isolation and team-level permissions are the next development stage.

No real customer or customs declaration data should be used during the current prototype stage.

## Development Roadmap

1. Supabase authentication
2. organisation-level tenant isolation
3. team and role-based access policies
4. backend workflow actions
5. internal case-management portal
6. supervisory review interface
7. customer status API
8. secure document handling
9. customer communication interface
10. controlled AI-assisted query handling
11. external system integration prototypes

## Status

Early-stage prototype development and practitioner validation.
