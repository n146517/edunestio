using EduNestIO.Common.DTOs;
using EduNestIO.WebServices.DataAccess;
using static EduNestIO.WebServices.Business.DBManagerDA;

namespace EduNestIO.WebServices.Business;

/// <summary>Business logic for the Assignments module.</summary>
public class AssignmentBL
{
    private static AssignmentDA Da() => (AssignmentDA)GetDBObject(DAType.Assignment)!;

    public DbResult Save(int tenantId, AssignmentVO vo)
    {
        AssignmentDA? da = null;
        try
        {
            da = Da();
            var payload = new
            {
                assignment_id = vo.AssignmentId,
                class_id = vo.ClassId,
                section_id = vo.SectionId,
                subject_id = vo.SubjectId,
                teacher_id = vo.TeacherId,
                title = vo.Title,
                description = vo.Description,
                due_date = vo.DueDate,
                max_marks = vo.MaxMarks
            };
            return da.Save(tenantId, payload);
        }
        finally { ReleaseDBObject(da); }
    }

    public DbResult List(int tenantId, long? classId, long? sectionId, long? subjectId)
    {
        AssignmentDA? da = null;
        try { da = Da(); return da.List(tenantId, classId, sectionId, subjectId); }
        finally { ReleaseDBObject(da); }
    }

    public DbResult ForStudent(int tenantId, long studentId)
    {
        AssignmentDA? da = null;
        try { da = Da(); return da.ForStudent(tenantId, studentId); }
        finally { ReleaseDBObject(da); }
    }

    public DbResult Submissions(int tenantId, long assignmentId)
    {
        AssignmentDA? da = null;
        try { da = Da(); return da.Submissions(tenantId, assignmentId); }
        finally { ReleaseDBObject(da); }
    }

    public DbResult Submit(int tenantId, long studentId, AssignmentSubmitVO vo)
    {
        AssignmentDA? da = null;
        try
        {
            da = Da();
            var payload = new { assignment_id = vo.AssignmentId, student_id = studentId, content = vo.Content };
            return da.Submit(tenantId, payload);
        }
        finally { ReleaseDBObject(da); }
    }

    public DbResult Grade(int tenantId, long actorUserId, AssignmentGradeVO vo)
    {
        AssignmentDA? da = null;
        try
        {
            da = Da();
            var payload = new { submission_id = vo.SubmissionId, marks = vo.Marks, feedback = vo.Feedback, actor_user_id = actorUserId };
            return da.Grade(tenantId, payload);
        }
        finally { ReleaseDBObject(da); }
    }

    public DbResult Delete(int tenantId, long assignmentId)
    {
        AssignmentDA? da = null;
        try { da = Da(); return da.Delete(tenantId, assignmentId); }
        finally { ReleaseDBObject(da); }
    }
}
