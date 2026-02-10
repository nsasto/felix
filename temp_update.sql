-- Update organization to untruaxioms with nsasto
UPDATE organizations 
SET 
  name = 'dev_org',
  slug = 'dev_org',
  owner_id = 'dev_user',
  metadata = '{"email": "devuser@gmail.com"}'::jsonb
WHERE id = '00000000-0000-0000-0000-000000000001';

-- Delete old member and insert new one
DELETE FROM organization_members 
WHERE org_id = '00000000-0000-0000-0000-000000000001';

INSERT INTO organization_members (org_id, user_id, role)
VALUES (
    '00000000-0000-0000-0000-000000000001',
    'dev_user',
    'owner'
);

SELECT 'Updated successfully' AS status;
