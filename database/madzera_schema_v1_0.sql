-- MADZERA MVP - MASTER POSTGRESQL SCHEMA
-- Version 1.0 | 2026-10-05
-- Structure only. RLS enabled; policies are not yet defined.
CREATE EXTENSION IF NOT EXISTS pgcrypto;

CREATE TABLE organisations (
 id UUID PRIMARY KEY DEFAULT gen_random_uuid(), name VARCHAR(255) NOT NULL,
 created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(), updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE TABLE users (
 id UUID PRIMARY KEY DEFAULT gen_random_uuid(), organisation_id UUID NOT NULL,
 email VARCHAR(320) NOT NULL, full_name VARCHAR(255) NOT NULL, role VARCHAR(50) NOT NULL,
 is_active BOOLEAN NOT NULL DEFAULT TRUE, created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
 updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
 CONSTRAINT fk_users_organisation FOREIGN KEY (organisation_id) REFERENCES organisations(id)
);
CREATE TABLE teams (
 id UUID PRIMARY KEY DEFAULT gen_random_uuid(), organisation_id UUID NOT NULL,
 name VARCHAR(255) NOT NULL, description TEXT, created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
 CONSTRAINT fk_teams_organisation FOREIGN KEY (organisation_id) REFERENCES organisations(id)
);
CREATE TABLE team_members (
 team_id UUID NOT NULL, user_id UUID NOT NULL, joined_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
 CONSTRAINT fk_team_members_team FOREIGN KEY (team_id) REFERENCES teams(id),
 CONSTRAINT fk_team_members_user FOREIGN KEY (user_id) REFERENCES users(id),
 CONSTRAINT uq_team_members UNIQUE (team_id,user_id)
);
CREATE TABLE customers (
 id UUID PRIMARY KEY DEFAULT gen_random_uuid(), organisation_id UUID NOT NULL,
 external_customer_id VARCHAR(255), name VARCHAR(255) NOT NULL, email VARCHAR(320),
 status VARCHAR(30) NOT NULL DEFAULT 'active', created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
 updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
 CONSTRAINT fk_customers_organisation FOREIGN KEY (organisation_id) REFERENCES organisations(id)
);
CREATE TABLE cases (
 id UUID PRIMARY KEY DEFAULT gen_random_uuid(), organisation_id UUID NOT NULL, customer_id UUID,
 assigned_team_id UUID, assigned_user_id UUID, title VARCHAR(500) NOT NULL, description TEXT,
 status VARCHAR(40) NOT NULL DEFAULT 'open', priority VARCHAR(20) NOT NULL DEFAULT 'normal',
 source VARCHAR(30) NOT NULL, external_case_id VARCHAR(255),
 created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(), updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
 resolved_at TIMESTAMPTZ,
 CONSTRAINT fk_cases_organisation FOREIGN KEY (organisation_id) REFERENCES organisations(id),
 CONSTRAINT fk_cases_customer FOREIGN KEY (customer_id) REFERENCES customers(id),
 CONSTRAINT fk_cases_assigned_team FOREIGN KEY (assigned_team_id) REFERENCES teams(id),
 CONSTRAINT fk_cases_assigned_user FOREIGN KEY (assigned_user_id) REFERENCES users(id)
);
CREATE TABLE case_events (
 id UUID PRIMARY KEY DEFAULT gen_random_uuid(), case_id UUID NOT NULL, organisation_id UUID NOT NULL,
 actor_user_id UUID, event_type VARCHAR(50) NOT NULL, from_status VARCHAR(40), to_status VARCHAR(40),
 from_team_id UUID, to_team_id UUID, from_user_id UUID, to_user_id UUID, details TEXT,
 created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
 CONSTRAINT fk_case_events_case FOREIGN KEY (case_id) REFERENCES cases(id),
 CONSTRAINT fk_case_events_organisation FOREIGN KEY (organisation_id) REFERENCES organisations(id),
 CONSTRAINT fk_case_events_actor FOREIGN KEY (actor_user_id) REFERENCES users(id),
 CONSTRAINT fk_case_events_from_team FOREIGN KEY (from_team_id) REFERENCES teams(id),
 CONSTRAINT fk_case_events_to_team FOREIGN KEY (to_team_id) REFERENCES teams(id),
 CONSTRAINT fk_case_events_from_user FOREIGN KEY (from_user_id) REFERENCES users(id),
 CONSTRAINT fk_case_events_to_user FOREIGN KEY (to_user_id) REFERENCES users(id)
);
CREATE TABLE comments (
 id UUID PRIMARY KEY DEFAULT gen_random_uuid(), case_id UUID NOT NULL, organisation_id UUID NOT NULL,
 author_user_id UUID, body TEXT NOT NULL, visibility VARCHAR(20) NOT NULL DEFAULT 'internal',
 created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(), updated_at TIMESTAMPTZ,
 CONSTRAINT fk_comments_case FOREIGN KEY (case_id) REFERENCES cases(id),
 CONSTRAINT fk_comments_organisation FOREIGN KEY (organisation_id) REFERENCES organisations(id),
 CONSTRAINT fk_comments_author FOREIGN KEY (author_user_id) REFERENCES users(id)
);
CREATE TABLE attachments (
 id UUID PRIMARY KEY DEFAULT gen_random_uuid(), case_id UUID NOT NULL, organisation_id UUID NOT NULL,
 uploaded_by_user_id UUID, uploaded_by_customer_id UUID, file_name VARCHAR(255) NOT NULL,
 file_type VARCHAR(100), file_size_bytes BIGINT, storage_reference TEXT NOT NULL,
 visibility VARCHAR(20) NOT NULL DEFAULT 'internal', created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
 CONSTRAINT fk_attachments_case FOREIGN KEY (case_id) REFERENCES cases(id),
 CONSTRAINT fk_attachments_organisation FOREIGN KEY (organisation_id) REFERENCES organisations(id),
 CONSTRAINT fk_attachments_user FOREIGN KEY (uploaded_by_user_id) REFERENCES users(id),
 CONSTRAINT fk_attachments_customer FOREIGN KEY (uploaded_by_customer_id) REFERENCES customers(id)
);
CREATE TABLE external_references (
 id UUID PRIMARY KEY DEFAULT gen_random_uuid(), organisation_id UUID NOT NULL, case_id UUID,
 customer_id UUID, system_name VARCHAR(100) NOT NULL, reference_type VARCHAR(50) NOT NULL,
 reference_value VARCHAR(255) NOT NULL, created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
 updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
 CONSTRAINT fk_external_references_organisation FOREIGN KEY (organisation_id) REFERENCES organisations(id),
 CONSTRAINT fk_external_references_case FOREIGN KEY (case_id) REFERENCES cases(id),
 CONSTRAINT fk_external_references_customer FOREIGN KEY (customer_id) REFERENCES customers(id)
);
CREATE TABLE case_tasks (
 id UUID PRIMARY KEY DEFAULT gen_random_uuid(), case_id UUID NOT NULL, organisation_id UUID NOT NULL,
 assigned_team_id UUID, assigned_user_id UUID, title VARCHAR(500) NOT NULL, description TEXT,
 status VARCHAR(40) NOT NULL DEFAULT 'open', priority VARCHAR(20) NOT NULL DEFAULT 'normal',
 due_at TIMESTAMPTZ, completed_at TIMESTAMPTZ, created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
 updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
 CONSTRAINT fk_case_tasks_case FOREIGN KEY (case_id) REFERENCES cases(id),
 CONSTRAINT fk_case_tasks_organisation FOREIGN KEY (organisation_id) REFERENCES organisations(id),
 CONSTRAINT fk_case_tasks_team FOREIGN KEY (assigned_team_id) REFERENCES teams(id),
 CONSTRAINT fk_case_tasks_user FOREIGN KEY (assigned_user_id) REFERENCES users(id)
);
CREATE TABLE case_reviews (
 id UUID PRIMARY KEY DEFAULT gen_random_uuid(), case_id UUID NOT NULL, organisation_id UUID NOT NULL,
 requested_by_user_id UUID, reviewer_user_id UUID, status VARCHAR(30) NOT NULL DEFAULT 'pending',
 review_type VARCHAR(40) NOT NULL, comments TEXT, requested_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
 completed_at TIMESTAMPTZ,
 CONSTRAINT fk_case_reviews_case FOREIGN KEY (case_id) REFERENCES cases(id),
 CONSTRAINT fk_case_reviews_organisation FOREIGN KEY (organisation_id) REFERENCES organisations(id),
 CONSTRAINT fk_case_reviews_requested_by FOREIGN KEY (requested_by_user_id) REFERENCES users(id),
 CONSTRAINT fk_case_reviews_reviewer FOREIGN KEY (reviewer_user_id) REFERENCES users(id)
);
CREATE TABLE conversations (
 id UUID PRIMARY KEY DEFAULT gen_random_uuid(), organisation_id UUID NOT NULL, customer_id UUID,
 channel VARCHAR(30) NOT NULL, status VARCHAR(30) NOT NULL DEFAULT 'open',
 external_conversation_id VARCHAR(255), started_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
 ended_at TIMESTAMPTZ, created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
 updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
 CONSTRAINT fk_conversations_organisation FOREIGN KEY (organisation_id) REFERENCES organisations(id),
 CONSTRAINT fk_conversations_customer FOREIGN KEY (customer_id) REFERENCES customers(id)
);
CREATE TABLE messages (
 id UUID PRIMARY KEY DEFAULT gen_random_uuid(), conversation_id UUID NOT NULL,
 organisation_id UUID NOT NULL, customer_id UUID, sender_user_id UUID,
 sender_type VARCHAR(20) NOT NULL, message_type VARCHAR(30) NOT NULL, body TEXT NOT NULL,
 created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
 CONSTRAINT fk_messages_conversation FOREIGN KEY (conversation_id) REFERENCES conversations(id),
 CONSTRAINT fk_messages_organisation FOREIGN KEY (organisation_id) REFERENCES organisations(id),
 CONSTRAINT fk_messages_customer FOREIGN KEY (customer_id) REFERENCES customers(id),
 CONSTRAINT fk_messages_sender_user FOREIGN KEY (sender_user_id) REFERENCES users(id)
);
CREATE TABLE conversation_cases (
 id UUID PRIMARY KEY DEFAULT gen_random_uuid(), conversation_id UUID NOT NULL, case_id UUID NOT NULL,
 created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
 CONSTRAINT fk_conversation_cases_conversation FOREIGN KEY (conversation_id) REFERENCES conversations(id),
 CONSTRAINT fk_conversation_cases_case FOREIGN KEY (case_id) REFERENCES cases(id),
 CONSTRAINT uq_conversation_cases UNIQUE (conversation_id,case_id)
);

ALTER TABLE organisations ENABLE ROW LEVEL SECURITY;
ALTER TABLE users ENABLE ROW LEVEL SECURITY;
ALTER TABLE teams ENABLE ROW LEVEL SECURITY;
ALTER TABLE team_members ENABLE ROW LEVEL SECURITY;
ALTER TABLE customers ENABLE ROW LEVEL SECURITY;
ALTER TABLE cases ENABLE ROW LEVEL SECURITY;
ALTER TABLE case_events ENABLE ROW LEVEL SECURITY;
ALTER TABLE comments ENABLE ROW LEVEL SECURITY;
ALTER TABLE attachments ENABLE ROW LEVEL SECURITY;
ALTER TABLE external_references ENABLE ROW LEVEL SECURITY;
ALTER TABLE case_tasks ENABLE ROW LEVEL SECURITY;
ALTER TABLE case_reviews ENABLE ROW LEVEL SECURITY;
ALTER TABLE conversations ENABLE ROW LEVEL SECURITY;
ALTER TABLE messages ENABLE ROW LEVEL SECURITY;
ALTER TABLE conversation_cases ENABLE ROW LEVEL SECURITY;
