using EduNestIO.Common.Data;
using EduNestIO.Common.DTOs;

namespace EduNestIO.WebServices.DataAccess;

/// <summary>Data access for the Attendance module.</summary>
public class AttendanceDA : DBBase
{
    public AttendanceDA(string connectionString = "") : base(connectionString) { }

    public DbResult Sheet(int tenantId, long classId, string attendDate, long? sectionId = null, long? subjectId = null) =>
        DAHelper.ExecuteTenantJson(DbMaster, "academics.fn_attendance_sheet", tenantId,
            new { class_id = classId, attend_date = attendDate, section_id = sectionId, subject_id = subjectId });

    public DbResult Mark(int tenantId, object payload) =>
        DAHelper.ExecuteTenantJson(DbMaster, "academics.fn_attendance_mark", tenantId, payload);

    public DbResult Register(int tenantId, long classId, int year, int month) =>
        DAHelper.ExecuteTenantJson(DbMaster, "academics.fn_attendance_register", tenantId,
            new { class_id = classId, year, month });

    public DbResult History(int tenantId, long studentId, int limit) =>
        DAHelper.ExecuteTenantJson(DbMaster, "academics.fn_attendance_history", tenantId,
            new { student_id = studentId, limit });

    public DbResult TodaySummary(int tenantId, string? attendDate) =>
        DAHelper.ExecuteTenantJson(DbMaster, "academics.fn_attendance_today_summary", tenantId,
            new { attend_date = attendDate });
}
