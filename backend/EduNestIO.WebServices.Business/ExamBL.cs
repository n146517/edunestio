using EduNestIO.Common.DTOs;
using EduNestIO.WebServices.DataAccess;
using static EduNestIO.WebServices.Business.DBManagerDA;

namespace EduNestIO.WebServices.Business;

/// <summary>Business logic for the Exams and Report Cards module.</summary>
public class ExamBL
{
    private static ExamDA Da() => (ExamDA)GetDBObject(DAType.Exam)!;

    public DbResult ExamSave(int tenantId, ExamVO vo)
    {
        ExamDA? da = null;
        try
        {
            da = Da();
            var payload = new
            {
                vo.ExamId,
                vo.Name,
                vo.ExamType,
                vo.AcademicYearId,
                StartDate = vo.StartDate?.ToString("yyyy-MM-dd"),
                EndDate = vo.EndDate?.ToString("yyyy-MM-dd"),
                vo.Description,
                ClassIds = vo.ClassIds
            };
            return da.ExamSave(tenantId, payload);
        }
        finally { ReleaseDBObject(da); }
    }

    public DbResult ExamList(int tenantId, ExamQueryVO q)
    {
        ExamDA? da = null;
        try
        {
            da = Da();
            var payload = new
            {
                search = q.Search,
                class_id = q.ClassId,
                academic_year_id = q.AcademicYearId,
                status = q.Status,
                exam_type = q.ExamType
            };
            return da.ExamList(tenantId, payload);
        }
        finally { ReleaseDBObject(da); }
    }

    public DbResult ExamGet(int tenantId, long examId)
    {
        ExamDA? da = null;
        try { da = Da(); return da.ExamGet(tenantId, examId); }
        finally { ReleaseDBObject(da); }
    }

    public DbResult SubjectAdd(int tenantId, ExamSubjectVO vo)
    {
        ExamDA? da = null;
        try
        {
            da = Da();
            return da.SubjectAdd(tenantId, new { vo.ExamId, vo.SubjectId, vo.MaxMarks, vo.PassMarks });
        }
        finally { ReleaseDBObject(da); }
    }

    public DbResult ClassSubjectsSave(int tenantId, ExamClassSubjectsVO vo)
    {
        ExamDA? da = null;
        try
        {
            da = Da();
            var payload = new
            {
                vo.ExamId,
                vo.ClassId,
                Subjects = vo.Subjects.Select(s => new
                {
                    s.ExamSubjectId, s.SubjectId, s.MaxMarks, s.PassMarks, s.SubjectType
                })
            };
            return da.ClassSubjectsSave(tenantId, payload);
        }
        finally { ReleaseDBObject(da); }
    }

    public DbResult ClassSubjectsList(int tenantId, long examId, long? classId)
    {
        ExamDA? da = null;
        try { da = Da(); return da.ClassSubjectsList(tenantId, examId, classId); }
        finally { ReleaseDBObject(da); }
    }

    public DbResult ScheduleSave(int tenantId, ExamScheduleSaveVO vo)
    {
        ExamDA? da = null;
        try
        {
            da = Da();
            var payload = new
            {
                vo.ExamId,
                Items = vo.Items.Select(i => new
                {
                    i.ExamSubjectId,
                    ExamDate = i.ExamDate?.ToString("yyyy-MM-dd"),
                    i.StartTime,
                    i.EndTime,
                    i.Room
                })
            };
            return da.ScheduleSave(tenantId, payload);
        }
        finally { ReleaseDBObject(da); }
    }

    public DbResult ScheduleList(int tenantId, long examId, long? classId)
    {
        ExamDA? da = null;
        try { da = Da(); return da.ScheduleList(tenantId, examId, classId); }
        finally { ReleaseDBObject(da); }
    }

    public DbResult MarksSheet(int tenantId, long examSubjectId, long? sectionId)
    {
        ExamDA? da = null;
        try { da = Da(); return da.MarksSheet(tenantId, examSubjectId, sectionId); }
        finally { ReleaseDBObject(da); }
    }

    public DbResult SubjectsForClass(int tenantId, long examId, long classId)
    {
        ExamDA? da = null;
        try { da = Da(); return da.SubjectsForClass(tenantId, examId, classId); }
        finally { ReleaseDBObject(da); }
    }

    public DbResult ResolveExamSubject(int tenantId, long examId, long classId, long subjectId)
    {
        ExamDA? da = null;
        try { da = Da(); return da.ResolveExamSubject(tenantId, examId, classId, subjectId); }
        finally { ReleaseDBObject(da); }
    }

    public DbResult MarksSave(int tenantId, long actorUserId, ExamMarksSaveVO vo)
    {
        ExamDA? da = null;
        try
        {
            da = Da();
            var payload = new
            {
                exam_subject_id = vo.ExamSubjectId,
                actor_user_id = actorUserId,
                entries = vo.Entries.Select(e => new
                {
                    student_id = e.StudentId,
                    marks = e.Marks,
                    is_absent = e.IsAbsent
                })
            };
            return da.MarksSave(tenantId, payload);
        }
        finally { ReleaseDBObject(da); }
    }

    public DbResult Publish(int tenantId, ExamPublishVO vo)
    {
        ExamDA? da = null;
        try { da = Da(); return da.Publish(tenantId, new { vo.ExamId, vo.Publish, vo.Force }); }
        finally { ReleaseDBObject(da); }
    }

    public DbResult ResultPreview(int tenantId, long examId, long classId, long? sectionId)
    {
        ExamDA? da = null;
        try { da = Da(); return da.ResultPreview(tenantId, examId, classId, sectionId); }
        finally { ReleaseDBObject(da); }
    }

    public DbResult ReportCard(int tenantId, long examId, long studentId, bool requirePublished)
    {
        ExamDA? da = null;
        try { da = Da(); return da.ReportCard(tenantId, examId, studentId, requirePublished); }
        finally { ReleaseDBObject(da); }
    }

    public DbResult ReportCardClassList(int tenantId, long examId, long classId, long? sectionId)
    {
        ExamDA? da = null;
        try { da = Da(); return da.ReportCardClassList(tenantId, examId, classId, sectionId); }
        finally { ReleaseDBObject(da); }
    }
}
