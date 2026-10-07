-- MADZERA MVP - SYNTHETIC DEMO SEED
-- Version 1.0 | 2026-10-06
-- ALL data below is fictional/synthetic.
-- Run only after madzera_schema_v1_0.sql on a fresh/demo database.
BEGIN;

INSERT INTO organisations (name)
SELECT 'NorthStar Customs Ltd'
WHERE NOT EXISTS (SELECT 1 FROM organisations WHERE name='NorthStar Customs Ltd');

INSERT INTO users (organisation_id,email,full_name,role)
SELECT o.id,v.email,v.full_name,v.role
FROM organisations o CROSS JOIN (VALUES
('sarah@northstar-demo.test','Sarah Mitchell','operations_analyst'),
('james@northstar-demo.test','James Carter','senior_analyst'),
('priya@northstar-demo.test','Priya Shah','compliance_analyst'),
('emma@northstar-demo.test','Emma Wilson','manager')
) v(email,full_name,role)
WHERE o.name='NorthStar Customs Ltd'
AND NOT EXISTS (SELECT 1 FROM users u WHERE u.email=v.email);

INSERT INTO teams (organisation_id,name,description)
SELECT o.id,v.name,v.description FROM organisations o CROSS JOIN (VALUES
('Customs Operations','Handles customs declaration and shipment-related operational cases.'),
('Customer Services','Handles general customer enquiries and first-line communication.'),
('Compliance','Handles compliance checks and higher-risk operational matters.'),
('Management','Provides operational oversight, escalation and supervisory review.')
) v(name,description)
WHERE o.name='NorthStar Customs Ltd'
AND NOT EXISTS (SELECT 1 FROM teams t WHERE t.organisation_id=o.id AND t.name=v.name);

INSERT INTO team_members(team_id,user_id)
SELECT t.id,u.id FROM teams t JOIN users u ON u.organisation_id=t.organisation_id
WHERE t.name='Customs Operations' AND u.email IN
('sarah@northstar-demo.test','james@northstar-demo.test','emma@northstar-demo.test')
ON CONFLICT (team_id,user_id) DO NOTHING;
INSERT INTO team_members(team_id,user_id)
SELECT t.id,u.id FROM teams t JOIN users u ON u.organisation_id=t.organisation_id
WHERE t.name='Compliance' AND u.email='priya@northstar-demo.test'
ON CONFLICT (team_id,user_id) DO NOTHING;
INSERT INTO team_members(team_id,user_id)
SELECT t.id,u.id FROM teams t JOIN users u ON u.organisation_id=t.organisation_id
WHERE t.name='Management' AND u.email='emma@northstar-demo.test'
ON CONFLICT (team_id,user_id) DO NOTHING;

INSERT INTO customers(organisation_id,external_customer_id,name,email)
SELECT o.id,'CUST-1001','ABC Imports Ltd','operations@abc-imports.test'
FROM organisations o WHERE o.name='NorthStar Customs Ltd'
AND NOT EXISTS (SELECT 1 FROM customers c WHERE c.organisation_id=o.id AND c.external_customer_id='CUST-1001');

INSERT INTO external_references(organisation_id,customer_id,system_name,reference_type,reference_value)
SELECT c.organisation_id,c.id,'Demo Declaration System','declaration_reference','DECL-DEMO-2026-001'
FROM customers c WHERE c.external_customer_id='CUST-1001'
AND NOT EXISTS (SELECT 1 FROM external_references er WHERE er.organisation_id=c.organisation_id AND er.reference_value='DECL-DEMO-2026-001');

INSERT INTO conversations(organisation_id,customer_id,channel,status,external_conversation_id)
SELECT c.organisation_id,c.id,'web_chatbot','open','CHAT-DEMO-001'
FROM customers c WHERE c.external_customer_id='CUST-1001'
AND NOT EXISTS (SELECT 1 FROM conversations x WHERE x.external_conversation_id='CHAT-DEMO-001');

INSERT INTO messages(conversation_id,organisation_id,customer_id,sender_type,message_type,body)
SELECT x.id,x.organisation_id,x.customer_id,'customer','text',
'Hi, can you tell me the current status of declaration DECL-DEMO-2026-001?'
FROM conversations x WHERE x.external_conversation_id='CHAT-DEMO-001'
AND NOT EXISTS (SELECT 1 FROM messages m WHERE m.conversation_id=x.id AND m.sender_type='customer');

INSERT INTO cases(organisation_id,customer_id,assigned_team_id,title,description,status,priority,source,external_case_id)
SELECT c.organisation_id,c.id,t.id,'Declaration status enquiry',
'Customer requested the current status of declaration DECL-DEMO-2026-001. Human review required.',
'open','normal','web_chatbot','CASE-DEMO-001'
FROM customers c JOIN teams t ON t.organisation_id=c.organisation_id
WHERE c.external_customer_id='CUST-1001' AND t.name='Customs Operations'
AND NOT EXISTS (SELECT 1 FROM cases ca WHERE ca.external_case_id='CASE-DEMO-001');

UPDATE external_references SET case_id=(SELECT id FROM cases WHERE external_case_id='CASE-DEMO-001')
WHERE reference_value='DECL-DEMO-2026-001';

INSERT INTO conversation_cases(conversation_id,case_id)
SELECT x.id,ca.id FROM conversations x CROSS JOIN cases ca
WHERE x.external_conversation_id='CHAT-DEMO-001' AND ca.external_case_id='CASE-DEMO-001'
ON CONFLICT (conversation_id,case_id) DO NOTHING;


INSERT INTO case_events(case_id,organisation_id,event_type,to_status,to_team_id,details)
SELECT ca.id,ca.organisation_id,'case_created','open',ca.assigned_team_id,
'Case created from web chatbot conversation after the enquiry required human review.'
FROM cases ca WHERE ca.external_case_id='CASE-DEMO-001'
AND NOT EXISTS (SELECT 1 FROM case_events ce WHERE ce.case_id=ca.id AND ce.event_type='case_created');

UPDATE cases SET assigned_user_id=(SELECT id FROM users WHERE email='sarah@northstar-demo.test'),
status='in_progress',updated_at=NOW() WHERE external_case_id='CASE-DEMO-001';

INSERT INTO case_events(case_id,organisation_id,actor_user_id,event_type,from_status,to_status,to_user_id,details)
SELECT ca.id,ca.organisation_id,u.id,'case_accepted','open','in_progress',u.id,
'Sarah Mitchell accepted ownership of the case from the Customs Operations queue.'
FROM cases ca JOIN users u ON u.organisation_id=ca.organisation_id
WHERE ca.external_case_id='CASE-DEMO-001' AND u.email='sarah@northstar-demo.test'
AND NOT EXISTS (SELECT 1 FROM case_events ce WHERE ce.case_id=ca.id AND ce.event_type='case_accepted');

INSERT INTO comments(case_id,organisation_id,author_user_id,body,visibility)
SELECT ca.id,ca.organisation_id,u.id,
'Declaration checked in the external system. Commercial invoice is required before processing can continue.','internal'
FROM cases ca JOIN users u ON u.organisation_id=ca.organisation_id
WHERE ca.external_case_id='CASE-DEMO-001' AND u.email='sarah@northstar-demo.test'
AND NOT EXISTS (SELECT 1 FROM comments c WHERE c.case_id=ca.id AND c.visibility='internal');

INSERT INTO comments(case_id,organisation_id,author_user_id,body,visibility)
SELECT ca.id,ca.organisation_id,u.id,
'We require the commercial invoice before we can continue processing this declaration.','customer'
FROM cases ca JOIN users u ON u.organisation_id=ca.organisation_id
WHERE ca.external_case_id='CASE-DEMO-001' AND u.email='sarah@northstar-demo.test'
AND NOT EXISTS (SELECT 1 FROM comments c WHERE c.case_id=ca.id AND c.visibility='customer');

INSERT INTO case_events(case_id,organisation_id,actor_user_id,event_type,details)
SELECT ca.id,ca.organisation_id,u.id,'customer_information_requested','Commercial invoice requested from customer.'
FROM cases ca JOIN users u ON u.organisation_id=ca.organisation_id
WHERE ca.external_case_id='CASE-DEMO-001' AND u.email='sarah@northstar-demo.test'
AND NOT EXISTS (SELECT 1 FROM case_events ce WHERE ce.case_id=ca.id AND ce.event_type='customer_information_requested');

INSERT INTO attachments(case_id,organisation_id,uploaded_by_customer_id,file_name,file_type,file_size_bytes,storage_reference,visibility)
SELECT ca.id,ca.organisation_id,ca.customer_id,'commercial_invoice_demo.pdf','application/pdf',245760,
'demo-storage/CASE-DEMO-001/commercial_invoice_demo.pdf','internal'
FROM cases ca WHERE ca.external_case_id='CASE-DEMO-001'
AND NOT EXISTS (SELECT 1 FROM attachments a WHERE a.case_id=ca.id AND a.storage_reference='demo-storage/CASE-DEMO-001/commercial_invoice_demo.pdf');

INSERT INTO case_events(case_id,organisation_id,event_type,details)
SELECT ca.id,ca.organisation_id,'customer_document_uploaded','Customer uploaded requested commercial invoice.'
FROM cases ca WHERE ca.external_case_id='CASE-DEMO-001'
AND NOT EXISTS (SELECT 1 FROM case_events ce WHERE ce.case_id=ca.id AND ce.event_type='customer_document_uploaded');


INSERT INTO case_reviews(case_id,organisation_id,requested_by_user_id,reviewer_user_id,status,review_type,comments)
SELECT ca.id,ca.organisation_id,s.id,j.id,'pending','four_eyes',
'Operational processing completed. Independent review required before case resolution.'
FROM cases ca
JOIN users s ON s.organisation_id=ca.organisation_id AND s.email='sarah@northstar-demo.test'
JOIN users j ON j.organisation_id=ca.organisation_id AND j.email='james@northstar-demo.test'
WHERE ca.external_case_id='CASE-DEMO-001'
AND NOT EXISTS (SELECT 1 FROM case_reviews cr WHERE cr.case_id=ca.id AND cr.review_type='four_eyes');

INSERT INTO case_events(case_id,organisation_id,actor_user_id,event_type,details)
SELECT ca.id,ca.organisation_id,u.id,'review_requested',
'Sarah Mitchell submitted the case for four-eyes review by James Carter.'
FROM cases ca JOIN users u ON u.organisation_id=ca.organisation_id
WHERE ca.external_case_id='CASE-DEMO-001' AND u.email='sarah@northstar-demo.test'
AND NOT EXISTS (SELECT 1 FROM case_events ce WHERE ce.case_id=ca.id AND ce.event_type='review_requested');

UPDATE case_reviews SET status='approved',
comments='Independent review completed. Processing verified and approved for case resolution.',
completed_at=COALESCE(completed_at,NOW())
WHERE case_id=(SELECT id FROM cases WHERE external_case_id='CASE-DEMO-001')
AND reviewer_user_id=(SELECT id FROM users WHERE email='james@northstar-demo.test')
AND review_type='four_eyes';

INSERT INTO case_events(case_id,organisation_id,actor_user_id,event_type,details)
SELECT ca.id,ca.organisation_id,u.id,'review_approved',
'James Carter completed and approved the four-eyes review.'
FROM cases ca JOIN users u ON u.organisation_id=ca.organisation_id
WHERE ca.external_case_id='CASE-DEMO-001' AND u.email='james@northstar-demo.test'
AND NOT EXISTS (SELECT 1 FROM case_events ce WHERE ce.case_id=ca.id AND ce.event_type='review_approved');

INSERT INTO comments(case_id,organisation_id,author_user_id,body,visibility)
SELECT ca.id,ca.organisation_id,u.id,
'The requested commercial invoice has been received and the required processing has been completed. This case is now resolved.','customer'
FROM cases ca JOIN users u ON u.organisation_id=ca.organisation_id
WHERE ca.external_case_id='CASE-DEMO-001' AND u.email='sarah@northstar-demo.test'
AND NOT EXISTS (SELECT 1 FROM comments c WHERE c.case_id=ca.id AND c.body LIKE 'The requested commercial invoice has been received%');

UPDATE cases SET status='resolved',resolved_at=COALESCE(resolved_at,NOW()),updated_at=NOW()
WHERE external_case_id='CASE-DEMO-001';

INSERT INTO case_events(case_id,organisation_id,actor_user_id,event_type,from_status,to_status,details)
SELECT ca.id,ca.organisation_id,u.id,'case_resolved','in_progress','resolved',
'Case resolved after completion of operational processing and approved four-eyes review.'
FROM cases ca JOIN users u ON u.organisation_id=ca.organisation_id
WHERE ca.external_case_id='CASE-DEMO-001' AND u.email='sarah@northstar-demo.test'
AND NOT EXISTS (SELECT 1 FROM case_events ce WHERE ce.case_id=ca.id AND ce.event_type='case_resolved');

COMMIT;

-- Verification: final case state
SELECT cu.name AS customer,ca.external_case_id,er.reference_value AS declaration_reference,
ca.status,t.name AS handling_team,u.full_name AS handled_by,ca.resolved_at,
(SELECT c.body FROM comments c WHERE c.case_id=ca.id AND c.visibility='customer'
 ORDER BY c.created_at DESC LIMIT 1) AS latest_customer_update
FROM cases ca JOIN customers cu ON ca.customer_id=cu.id
LEFT JOIN teams t ON ca.assigned_team_id=t.id
LEFT JOIN users u ON ca.assigned_user_id=u.id
LEFT JOIN external_references er ON er.case_id=ca.id AND er.reference_type='declaration_reference'
WHERE ca.external_case_id='CASE-DEMO-001';

-- Verification: complete audit history
SELECT ce.created_at,ce.event_type,u.full_name AS actor,ce.from_status,ce.to_status,ce.details
FROM case_events ce JOIN cases ca ON ce.case_id=ca.id
LEFT JOIN users u ON ce.actor_user_id=u.id
WHERE ca.external_case_id='CASE-DEMO-001'
ORDER BY ce.created_at;
