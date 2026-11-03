using EduNestIO.Common.DTOs;
using EduNestIO.WebServices.DataAccess;
using static EduNestIO.WebServices.Business.DBManagerDA;

namespace EduNestIO.WebServices.Business;

/// <summary>Business logic for the Timetable module.</summary>
public class TimetableBL
{
    private static TimetableDA Da() => (TimetableDA)GetDBObject(DAType.Timetable)!;

    public DbResult Save(int tenantId, TimetableSlotVO vo)
    {
        TimetableDA? da = null;
        try
        {
            da = Da();
            var payload = new
            {
                slot_id = vo.SlotId,
                class_id = vo.ClassId,
                section_id = vo.SectionId,
                day_of_week = vo.DayOfWeek,
                period_no = vo.PeriodNo,
                start_time = vo.StartTime,
                end_time = vo.EndTime,
                subject_id = vo.SubjectId,
                teacher_id = vo.TeacherId,
                room = vo.Room
            };
            return da.Save(tenantId, payload);
        }
        finally { ReleaseDBObject(da); }
    }

    public DbResult List(int tenantId, long classId, long? sectionId)
    {
        TimetableDA? da = null;
        try { da = Da(); return da.List(tenantId, classId, sectionId); }
        finally { ReleaseDBObject(da); }
    }

    public DbResult ForStudent(int tenantId, long studentId)
    {
        TimetableDA? da = null;
        try { da = Da(); return da.ForStudent(tenantId, studentId); }
        finally { ReleaseDBObject(da); }
    }

    public DbResult Delete(int tenantId, long slotId)
    {
        TimetableDA? da = null;
        try { da = Da(); return da.Delete(tenantId, slotId); }
        finally { ReleaseDBObject(da); }
    }

    public DbResult Teachers(int tenantId)
    {
        TimetableDA? da = null;
        try { da = Da(); return da.Teachers(tenantId); }
        finally { ReleaseDBObject(da); }
    }
}
