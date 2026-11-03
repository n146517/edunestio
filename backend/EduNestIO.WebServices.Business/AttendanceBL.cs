using EduNestIO.Common.DTOs;
using EduNestIO.WebServices.DataAccess;
using static EduNestIO.WebServices.Business.DBManagerDA;

namespace EduNestIO.WebServices.Business;

/// <summary>Business logic for the Attendance module.</summary>
public class AttendanceBL
{
    private static AttendanceDA Da() => (AttendanceDA)GetDBObject(DAType.Attendance)!;

    public DbResult Sheet(int tenantId, long classId, string attendDate, long? sectionId = null, long? subjectId = null)
    {
        AttendanceDA? da = null;
        try { da = Da(); return da.Sheet(tenantId, classId, attendDate, sectionId, subjectId); }
        finally { ReleaseDBObject(da); }
    }

    public DbResult Mark(int tenantId, long actorUserId, AttendanceMarkVO vo)
    {
        AttendanceDA? da = null;
        try
        {
            da = Da();
            var payload = new
            {
                class_id = vo.ClassId,
                section_id = vo.SectionId,
                subject_id = vo.SubjectId,
                attend_date = vo.AttendDate.ToString("yyyy-MM-dd"),
                actor_user_id = actorUserId,
                entries = vo.Entries.Select(e => new
                {
                    student_id = e.StudentId,
                    status = e.Status,
                    remark = e.Remark
                })
            };
            return da.Mark(tenantId, payload);
        }
        finally { ReleaseDBObject(da); }
    }

    public DbResult Register(int tenantId, long classId, int year, int month)
    {
        AttendanceDA? da = null;
        try { da = Da(); return da.Register(tenantId, classId, year, month); }
        finally { ReleaseDBObject(da); }
    }

    public DbResult History(int tenantId, long studentId, int limit)
    {
        AttendanceDA? da = null;
        try { da = Da(); return da.History(tenantId, studentId, limit); }
        finally { ReleaseDBObject(da); }
    }

    public DbResult TodaySummary(int tenantId, string? attendDate)
    {
        AttendanceDA? da = null;
        try { da = Da(); return da.TodaySummary(tenantId, attendDate); }
        finally { ReleaseDBObject(da); }
    }
}
