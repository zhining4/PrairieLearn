-- BLOCK select_authz_data
SELECT
    coalesce($force_mode, ip_to_mode($ip, $req_date)) AS mode,
    to_jsonb(c.*) AS course,
    to_jsonb(ci.*) AS course_instance,
    permissions_course.*,
    permissions_course_instance.*,
    courses_with_staff_access($authn_user_id, $is_administrator) AS courses,
    course_instances_with_staff_access($authn_user_id, $is_administrator, coalesce($course_id, ci.course_id)) AS course_instances
FROM
    pl_courses AS c
    LEFT JOIN course_instances AS ci ON (c.id = ci.course_id) AND (ci.id = $course_instance_id) AND (ci.deleted_at IS NULL)
    JOIN LATERAL authz_course($authn_user_id, c.id, $is_administrator, $req_course_role) AS permissions_course ON TRUE
    JOIN LATERAL authz_course_instance($authn_user_id, ci.id, $is_administrator, $req_date, $req_course_instance_role) AS permissions_course_instance ON TRUE
WHERE
    c.id = coalesce($course_id, ci.course_id)
    AND c.deleted_at IS NULL
    AND (
            (permissions_course->>'course_role')::enum_course_role > 'None'
            OR (permissions_course_instance->>'course_instance_role')::enum_course_instance_role > 'None'
            OR (permissions_course_instance->>'is_enrolled_with_access')::boolean IS TRUE
        );

-- BLOCK ensure_enrollment
INSERT INTO enrollments
        (course_instance_id,  user_id,  role)
VALUES ($course_instance_id, $user_id, $role)
ON CONFLICT (user_id, course_instance_id) DO NOTHING;

-- BLOCK select_user
SELECT
    to_jsonb(u) AS user,
    to_jsonb(i) AS institution,
    (adm.id IS NOT NULL) AS is_administrator
FROM
    users AS u
    LEFT JOIN administrators AS adm ON (adm.user_id = u.user_id)
    JOIN institutions AS i ON (i.id = u.institution_id)
WHERE
    u.uid = $uid;

-- BLOCK select_effective_authz_data
WITH effective_data AS (
    SELECT
        CASE
            WHEN $authn_course_role::enum_course_role >= 'Previewer' AND e.role <= $authn_role::enum_role THEN to_jsonb(u)
            ELSE to_jsonb(authn_u)
        END AS user,
        CASE
            WHEN $authn_course_role::enum_course_role >= 'TA' THEN least($authn_role::enum_role, $requested_role::enum_role)
            ELSE $authn_role::enum_role
        END AS role,
        CASE
            WHEN $authn_role::enum_role >= 'TA' THEN $requested_mode::enum_mode
            ELSE $server_mode::enum_mode
        END AS mode,
        CASE
            WHEN $authn_role::enum_role >= 'Instructor' THEN $requested_date::timestamptz
            ELSE $req_date
        END AS req_date
    FROM
        users AS authn_u,
        users AS u
        JOIN enrollments AS e ON (e.user_id = u.user_id AND e.course_instance_id = $course_instance_id)
    WHERE
        authn_u.user_id = $authn_user_id
        AND u.uid = $requested_uid
)
SELECT
    ed.*,
    authz_course((ed.user->>'user_id')::bigint, c.id, FALSE) AS permissions_course,
    (ed.role >= 'TA') AS has_instructor_view,
    (ed.role >= 'Instructor') AS has_instructor_edit
FROM
    effective_data AS ed
    JOIN course_instances AS ci ON (ci.id = $course_instance_id AND ci.deleted_at IS NULL)
    JOIN pl_courses AS c ON (c.id = ci.course_id AND c.deleted_at IS NULL)
WHERE
    ed.role IS NOT NULL
    AND check_course_instance_access($course_instance_id, ed.role, ed.user->>'uid', (ed.user->>'institution_id')::bigint, ed.req_date);



-- BLOCK select_effective_authz_data_old
WITH effective_data AS (
    SELECT
        CASE
            WHEN $authn_role::enum_role >= 'TA' AND e.role <= $authn_role::enum_role THEN to_jsonb(u)
            ELSE to_jsonb(authn_u)
        END AS user,
        CASE
            WHEN $authn_role::enum_role >= 'TA' THEN least($authn_role::enum_role, $requested_role::enum_role)
            ELSE $authn_role::enum_role
        END AS role,
        CASE
            WHEN $authn_role::enum_role >= 'TA' THEN $requested_mode::enum_mode
            ELSE $server_mode::enum_mode
        END AS mode,
        CASE
            WHEN $authn_role::enum_role >= 'Instructor' THEN $requested_date::timestamptz
            ELSE $req_date
        END AS req_date
    FROM
        users AS authn_u,
        users AS u
        JOIN enrollments AS e ON (e.user_id = u.user_id AND e.course_instance_id = $course_instance_id)
    WHERE
        authn_u.user_id = $authn_user_id
        AND u.uid = $requested_uid
)
SELECT
    ed.*,
    authz_course((ed.user->>'user_id')::bigint, c.id, FALSE) AS permissions_course,
    (ed.role >= 'TA') AS has_instructor_view,
    (ed.role >= 'Instructor') AS has_instructor_edit
FROM
    effective_data AS ed
    JOIN course_instances AS ci ON (ci.id = $course_instance_id AND ci.deleted_at IS NULL)
    JOIN pl_courses AS c ON (c.id = ci.course_id AND c.deleted_at IS NULL)
WHERE
    ed.role IS NOT NULL
    AND check_course_instance_access($course_instance_id, ed.role, ed.user->>'uid', (ed.user->>'institution_id')::bigint, ed.req_date);