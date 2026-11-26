SELECT
    role,
    status,
    COUNT(*) AS member_count
FROM public.couple_members
GROUP BY role, status
ORDER BY role;