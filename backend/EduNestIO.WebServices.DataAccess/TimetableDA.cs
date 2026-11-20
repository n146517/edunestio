using EduNestIO.Common.Data;
using EduNestIO.Common.DTOs;

namespace EduNestIO.WebServices.DataAccess;

/// <summary>Data access for the Timetable module.</summary>
public class TimetableDA : DBBase
{
    public TimetableDA(string connectionString = "") : base(connectionString) { }

    public DbResult Save(int tenantId, object payload) =>
        DAHelper.ExecuteTenantJson(DbMaster, "academics.fn_timetable_save", tenantId, payload);

    public DbResult List(int tenantId, long classId, long? sectionId) =>
        DAHelper.ExecuteTenantJson(DbMaster, "academics.fn_timetable_list", tenantId,
            new { class_id = classId, section_id = sectionId });

    public DbResult ForStudent(int tenantId, long studentId) =>
        DAHelper.ExecuteTenantJson(DbMaster, "academics.fn_timetable_for_student", tenantId,
            new { student_id = studentId });

    public DbResult Delete(int tenantId, long slotId) =>
        DAHelper.ExecuteTenantJson(DbMaster, "academics.fn_timetable_delete", tenantId,
            new { slot_id = slotId });

    public DbResult ScheduleGet(int tenantId, long classId) =>
        DAHelper.ExecuteTenantJson(DbMaster, "academics.fn_period_schedule_get", tenantId,
            new { class_id = classId });

    public DbResult ScheduleSave(int tenantId, object payload) =>
        DAHelper.ExecuteTenantJson(DbMaster, "academics.fn_period_schedule_save", tenantId, payload);

    public DbResult TeacherSchedule(int tenantId, long teacherId) =>
        DAHelper.ExecuteTenantJson(DbMaster, "academics.fn_teacher_schedule", tenantId,
            new { teacher_id = teacherId });

    public DbResult Teachers(int tenantId) =>
        DAHelper.ExecuteTenantJson(DbMaster, "core.fn_teacher_list", tenantId, new { });
}
