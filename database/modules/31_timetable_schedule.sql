-- =============================================================================
-- EduNestIO :: Module — Class-wise period schedule + teacher clash check
-- (31_timetable_schedule.sql)
--   * academics.period_schedule: per CLASS ordered rows of Period / Break / Lunch
--     with start+end time. The principal edits it; the timetable grid is built
--     from it (so a school/class can have fewer or more periods, breaks, lunch).
--   * fn_timetable_save now REJECTS a teacher double-booking (same teacher, same
--     day, overlapping time, in another class/section) and lists where.
--   * fn_teacher_schedule: everything a teacher teaches (class, day, time).
--   * fn_timetable_for_student also returns the class's schedule.
-- Idempotent. Apply after module 30.
-- =============================================================================

CREATE TABLE IF NOT EXISTS academics.period_schedule (
    schedule_id bigserial    PRIMARY KEY,
    tenant_id   integer      NOT NULL REFERENCES core.tenant(tenant_id) ON DELETE RESTRICT,
    class_id    bigint       NOT NULL REFERENCES academics.school_class(class_id) ON DELETE CASCADE,
    seq         smallint     NOT NULL,                 -- column order within the day
    kind        varchar(10)  NOT NULL DEFAULT 'Period',-- Period | Break | Lunch
    label       varchar(40)  NOT NULL,
    period_no   smallint     NULL,                     -- only for kind = 'Period' (1,2,3...)
    start_time  time         NOT NULL,
    end_time    time         NOT NULL,
    CONSTRAINT ck_ps_kind CHECK (kind IN ('Period','Break','Lunch')),
    CONSTRAINT ck_ps_time CHECK (end_time > start_time),
    CONSTRAINT uq_ps_seq UNIQUE (tenant_id, class_id, seq)
);

-- ---- Get a class's schedule. Payload: { class_id } -------------------------
CREATE OR REPLACE FUNCTION academics.fn_period_schedule_get(p_tenant_id integer, p_payload jsonb)
RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE v_class bigint := NULLIF(p_payload->>'class_id','')::bigint; v jsonb;
BEGIN
    IF v_class IS NULL THEN
        RETURN jsonb_build_object('result_code',3,'message','class_id required','data',NULL);
    END IF;
    SELECT COALESCE(jsonb_agg(row_to_json(t) ORDER BY t.seq),'[]'::jsonb) INTO v FROM (
        SELECT seq, kind, label, period_no,
               to_char(start_time,'HH24:MI') AS start_time, to_char(end_time,'HH24:MI') AS end_time
          FROM academics.period_schedule
         WHERE tenant_id=p_tenant_id AND class_id=v_class
    ) t;
    RETURN jsonb_build_object('result_code',0,'message','Success','data',jsonb_build_object('items',v));
END; $$;

-- ---- Replace a class's schedule. Payload:
--   { class_id, items:[{ kind, label, start_time, end_time }, ...] } (in display order)
CREATE OR REPLACE FUNCTION academics.fn_period_schedule_save(p_tenant_id integer, p_payload jsonb)
RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE v_class bigint := NULLIF(p_payload->>'class_id','')::bigint;
        v_items jsonb := COALESCE(p_payload->'items','[]'::jsonb);
        it jsonb; v_seq smallint := 0; v_pno smallint := 0;
        v_kind text; v_label text; v_s time; v_e time; v_prev_end time := NULL;
        v_removed integer := 0;
BEGIN
    IF v_class IS NULL THEN
        RETURN jsonb_build_object('result_code',3,'message','class_id required','data',NULL);
    END IF;
    IF NOT EXISTS (SELECT 1 FROM academics.school_class WHERE class_id=v_class AND tenant_id=p_tenant_id) THEN
        RETURN jsonb_build_object('result_code',4,'message','Class not found','data',NULL);
    END IF;
    IF jsonb_array_length(v_items) = 0 THEN
        RETURN jsonb_build_object('result_code',3,'message','Add at least one period.','data',NULL);
    END IF;

    -- Validate first (kinds, times, order, no overlap) so nothing is half-saved.
    FOR it IN SELECT * FROM jsonb_array_elements(v_items) LOOP
        v_kind := COALESCE(NULLIF(it->>'kind',''),'Period');
        v_label := COALESCE(NULLIF(trim(it->>'label'),''), v_kind);
        v_s := NULLIF(it->>'start_time','')::time;
        v_e := NULLIF(it->>'end_time','')::time;
        IF v_kind NOT IN ('Period','Break','Lunch') THEN
            RETURN jsonb_build_object('result_code',3,'message','Invalid type for "'||v_label||'".','data',NULL);
        END IF;
        IF v_s IS NULL OR v_e IS NULL THEN
            RETURN jsonb_build_object('result_code',3,'message','Start and end time are required for "'||v_label||'".','data',NULL);
        END IF;
        IF v_e <= v_s THEN
            RETURN jsonb_build_object('result_code',3,'message','End time must be after start time for "'||v_label||'".','data',NULL);
        END IF;
        IF v_prev_end IS NOT NULL AND v_s < v_prev_end THEN
            RETURN jsonb_build_object('result_code',3,'message','"'||v_label||'" starts before the previous row ends. Keep rows in time order without overlap.','data',NULL);
        END IF;
        v_prev_end := v_e;
    END LOOP;

    DELETE FROM academics.period_schedule WHERE tenant_id=p_tenant_id AND class_id=v_class;
    FOR it IN SELECT * FROM jsonb_array_elements(v_items) LOOP
        v_seq := v_seq + 1;
        v_kind := COALESCE(NULLIF(it->>'kind',''),'Period');
        IF v_kind = 'Period' THEN v_pno := v_pno + 1; END IF;
        INSERT INTO academics.period_schedule (tenant_id, class_id, seq, kind, label, period_no, start_time, end_time)
        VALUES (p_tenant_id, v_class, v_seq, v_kind,
                COALESCE(NULLIF(trim(it->>'label'),''), CASE WHEN v_kind='Period' THEN 'P'||v_pno ELSE v_kind END),
                CASE WHEN v_kind='Period' THEN v_pno ELSE NULL END,
                (it->>'start_time')::time, (it->>'end_time')::time);
    END LOOP;

    -- Slots for periods that no longer exist are cleared.
    DELETE FROM academics.timetable_slot
     WHERE tenant_id=p_tenant_id AND class_id=v_class AND period_no > v_pno;
    GET DIAGNOSTICS v_removed = ROW_COUNT;

    -- Keep existing slot times in step with the schedule.
    UPDATE academics.timetable_slot ts
       SET start_time = ps.start_time, end_time = ps.end_time, updated_at = now()
      FROM academics.period_schedule ps
     WHERE ts.tenant_id=p_tenant_id AND ts.class_id=v_class
       AND ps.tenant_id=ts.tenant_id AND ps.class_id=ts.class_id
       AND ps.kind='Period' AND ps.period_no=ts.period_no;

    RETURN jsonb_build_object('result_code',0,'message','Saved',
        'data',jsonb_build_object('periods',v_pno,'rows',v_seq,'removed_slots',v_removed));
EXCEPTION WHEN OTHERS THEN RETURN jsonb_build_object('result_code',1,'message',SQLERRM,'data',NULL);
END; $$;

-- ---- Save one slot, rejecting teacher double-booking -----------------------
CREATE OR REPLACE FUNCTION academics.fn_timetable_save(p_tenant_id integer, p_payload jsonb)
RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE v_id bigint := NULLIF(p_payload->>'slot_id','')::bigint;
        v_class bigint := NULLIF(p_payload->>'class_id','')::bigint;
        v_section bigint := NULLIF(p_payload->>'section_id','')::bigint;
        v_day smallint := NULLIF(p_payload->>'day_of_week','')::smallint;
        v_period smallint := NULLIF(p_payload->>'period_no','')::smallint;
        v_teacher bigint := NULLIF(p_payload->>'teacher_id','')::bigint;
        v_start time := NULLIF(p_payload->>'start_time','')::time;
        v_end   time := NULLIF(p_payload->>'end_time','')::time;
        v_owner integer; v_conf text; v_tname text;
        v_days text[] := ARRAY['Monday','Tuesday','Wednesday','Thursday','Friday','Saturday','Sunday'];
BEGIN
    IF v_class IS NULL OR v_day IS NULL OR v_period IS NULL THEN
        RETURN jsonb_build_object('result_code',3,'message','class, day and period are required','data',NULL);
    END IF;

    -- Times come from the class schedule when it defines this period.
    SELECT ps.start_time, ps.end_time INTO v_start, v_end
      FROM academics.period_schedule ps
     WHERE ps.tenant_id=p_tenant_id AND ps.class_id=v_class AND ps.kind='Period' AND ps.period_no=v_period
     LIMIT 1;
    IF NOT FOUND THEN
        v_start := NULLIF(p_payload->>'start_time','')::time;
        v_end   := NULLIF(p_payload->>'end_time','')::time;
    END IF;

    -- Teacher clash: same teacher, same day, overlapping time, in another cell.
    IF v_teacher IS NOT NULL THEN
        SELECT string_agg(
                 COALESCE(c.name,'Class')||COALESCE(' '||sec.name,' (all sections)')||' · '||v_days[o.day_of_week]
                 ||CASE WHEN o.start_time IS NOT NULL THEN ' · '||to_char(o.start_time,'HH24:MI')||'–'||to_char(o.end_time,'HH24:MI')
                        ELSE ' · P'||o.period_no END
                 ||COALESCE(' · '||sub.name,''), '|' ORDER BY o.start_time, o.period_no)
          INTO v_conf
          FROM academics.timetable_slot o
          LEFT JOIN academics.school_class  c   ON c.class_id=o.class_id
          LEFT JOIN academics.class_section sec ON sec.section_id=o.section_id
          LEFT JOIN academics.subject       sub ON sub.subject_id=o.subject_id
         WHERE o.tenant_id=p_tenant_id AND o.teacher_id=v_teacher AND o.day_of_week=v_day
           AND NOT (o.class_id=v_class AND COALESCE(o.section_id,0)=COALESCE(v_section,0) AND o.period_no=v_period)
           AND (v_id IS NULL OR o.slot_id<>v_id)
           AND ( (v_start IS NOT NULL AND v_end IS NOT NULL AND o.start_time IS NOT NULL AND o.end_time IS NOT NULL
                  AND o.start_time < v_end AND v_start < o.end_time)
              OR ((v_start IS NULL OR v_end IS NULL OR o.start_time IS NULL OR o.end_time IS NULL)
                  AND o.period_no=v_period) );
        IF v_conf IS NOT NULL THEN
            SELECT COALESCE(full_name, username) INTO v_tname FROM core.app_user WHERE user_id=v_teacher;
            RETURN jsonb_build_object('result_code',7,
                'message', COALESCE(v_tname,'This teacher')||' is already teaching at this time ('||v_days[v_day]
                           ||CASE WHEN v_start IS NOT NULL THEN ' '||to_char(v_start,'HH24:MI')||'–'||to_char(v_end,'HH24:MI') ELSE '' END
                           ||') in:|'||v_conf,
                'data',NULL);
        END IF;
    END IF;

    IF v_id IS NULL THEN
        INSERT INTO academics.timetable_slot
            (tenant_id, class_id, section_id, day_of_week, period_no, start_time, end_time, subject_id, teacher_id, room)
        VALUES (p_tenant_id, v_class, v_section, v_day, v_period, v_start, v_end,
                NULLIF(p_payload->>'subject_id','')::bigint, v_teacher, NULLIF(p_payload->>'room',''))
        ON CONFLICT (tenant_id, class_id, COALESCE(section_id,0), day_of_week, period_no)
        DO UPDATE SET start_time=EXCLUDED.start_time, end_time=EXCLUDED.end_time,
                      subject_id=EXCLUDED.subject_id, teacher_id=EXCLUDED.teacher_id,
                      room=EXCLUDED.room, updated_at=now()
        RETURNING slot_id INTO v_id;
    ELSE
        SELECT tenant_id INTO v_owner FROM academics.timetable_slot WHERE slot_id=v_id;
        IF v_owner IS NULL OR v_owner<>p_tenant_id THEN
            RETURN jsonb_build_object('result_code',4,'message','Slot not found','data',NULL);
        END IF;
        UPDATE academics.timetable_slot SET
            class_id=v_class, section_id=v_section, day_of_week=v_day, period_no=v_period,
            start_time=v_start, end_time=v_end,
            subject_id=NULLIF(p_payload->>'subject_id','')::bigint, teacher_id=v_teacher,
            room=NULLIF(p_payload->>'room',''), updated_at=now()
         WHERE slot_id=v_id AND tenant_id=p_tenant_id;
    END IF;
    RETURN jsonb_build_object('result_code',0,'message','Saved','data',jsonb_build_object('slot_id',v_id));
EXCEPTION WHEN unique_violation THEN
    RETURN jsonb_build_object('result_code',7,'message','That day + period already has a slot for this class/section','data',NULL);
WHEN OTHERS THEN RETURN jsonb_build_object('result_code',1,'message',SQLERRM,'data',NULL);
END; $$;

-- ---- Everything one teacher teaches. Payload: { teacher_id } ----------------
CREATE OR REPLACE FUNCTION academics.fn_teacher_schedule(p_tenant_id integer, p_payload jsonb)
RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE v_t bigint := NULLIF(p_payload->>'teacher_id','')::bigint; v jsonb; v_name text;
BEGIN
    IF v_t IS NULL THEN
        RETURN jsonb_build_object('result_code',3,'message','teacher_id required','data',NULL);
    END IF;
    SELECT COALESCE(full_name, username) INTO v_name
      FROM core.app_user WHERE user_id=v_t AND tenant_id=p_tenant_id;
    IF v_name IS NULL THEN
        RETURN jsonb_build_object('result_code',4,'message','Teacher not found','data',NULL);
    END IF;
    SELECT COALESCE(jsonb_agg(row_to_json(t) ORDER BY t.day_of_week, t.start_time, t.period_no),'[]'::jsonb) INTO v FROM (
        SELECT ts.slot_id, ts.class_id, c.name AS class_name, ts.section_id, sec.name AS section_name,
               ts.day_of_week, ts.period_no, to_char(ts.start_time,'HH24:MI') AS start_time,
               to_char(ts.end_time,'HH24:MI') AS end_time, sub.name AS subject_name, ts.room
          FROM academics.timetable_slot ts
          LEFT JOIN academics.school_class  c   ON c.class_id=ts.class_id
          LEFT JOIN academics.class_section sec ON sec.section_id=ts.section_id
          LEFT JOIN academics.subject       sub ON sub.subject_id=ts.subject_id
         WHERE ts.tenant_id=p_tenant_id AND ts.teacher_id=v_t
    ) t;
    RETURN jsonb_build_object('result_code',0,'message','Success',
        'data',jsonb_build_object('teacher_id',v_t,'teacher_name',v_name,'items',v));
END; $$;

-- ---- Student timetable now also carries the class schedule -------------------
CREATE OR REPLACE FUNCTION academics.fn_timetable_for_student(p_tenant_id integer, p_payload jsonb)
RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE v_sid bigint := (p_payload->>'student_id')::bigint; v_class bigint; v_section bigint;
        v jsonb; v_sched jsonb;
BEGIN
    SELECT class_id, section_id INTO v_class, v_section
      FROM academics.student WHERE student_id=v_sid AND tenant_id=p_tenant_id;
    IF v_class IS NULL THEN
        RETURN jsonb_build_object('result_code',0,'message','No class',
            'data',jsonb_build_object('items','[]'::jsonb,'schedule','[]'::jsonb));
    END IF;
    SELECT COALESCE(jsonb_agg(row_to_json(t) ORDER BY t.day_of_week, t.period_no),'[]'::jsonb) INTO v FROM (
        SELECT ts.slot_id, ts.day_of_week, ts.period_no,
               ts.start_time::text AS start_time, ts.end_time::text AS end_time,
               sub.name AS subject_name, COALESCE(u.full_name,u.username) AS teacher_name, ts.room
          FROM academics.timetable_slot ts
          LEFT JOIN academics.subject sub ON sub.subject_id=ts.subject_id
          LEFT JOIN core.app_user u ON u.user_id=ts.teacher_id
         WHERE ts.tenant_id=p_tenant_id AND ts.class_id=v_class
           AND (ts.section_id IS NULL OR ts.section_id = v_section)
    ) t;
    SELECT COALESCE(jsonb_agg(row_to_json(s) ORDER BY s.seq),'[]'::jsonb) INTO v_sched FROM (
        SELECT seq, kind, label, period_no,
               to_char(start_time,'HH24:MI') AS start_time, to_char(end_time,'HH24:MI') AS end_time
          FROM academics.period_schedule WHERE tenant_id=p_tenant_id AND class_id=v_class
    ) s;
    RETURN jsonb_build_object('result_code',0,'message','Success',
        'data',jsonb_build_object('items',v,'schedule',v_sched));
END; $$;
