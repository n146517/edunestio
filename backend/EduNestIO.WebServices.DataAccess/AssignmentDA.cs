using EduNestIO.Common.Data;
using EduNestIO.Common.DTOs;

namespace EduNestIO.WebServices.DataAccess;

/// <summary>Data access for the Assignments module.</summary>
public class AssignmentDA : DBBase
{
    public AssignmentDA(string connectionString = "") : base(connectionString) { }

    public DbResult Save(int tenantId, object payload) =>
        DAHelper.ExecuteTenantJson(DbMaster, "academics.fn_assignment_save", tenantId, payload);

    public DbResult List(int tenantId, long? classId, long? sectionId, long? subjectId) =>
        DAHelper.ExecuteTenantJson(DbMaster, "academics.fn_assignment_list", tenantId,
            new { class_id = classId, section_id = sectionId, subject_id = subjectId });

    public DbResult ForStudent(int tenantId, long studentId) =>
        DAHelper.ExecuteTenantJson(DbMaster, "academics.fn_assignment_for_student", tenantId,
            new { student_id = studentId });

    public DbResult Submissions(int tenantId, long assignmentId) =>
        DAHelper.ExecuteTenantJson(DbMaster, "academics.fn_assignment_submissions", tenantId,
            new { assignment_id = assignmentId });

    public DbResult Submit(int tenantId, object payload) =>
        DAHelper.ExecuteTenantJson(DbMaster, "academics.fn_assignment_submit", tenantId, payload);

    public DbResult Grade(int tenantId, object payload) =>
        DAHelper.ExecuteTenantJson(DbMaster, "academics.fn_assignment_grade", tenantId, payload);

    public DbResult Delete(int tenantId, long assignmentId) =>
        DAHelper.ExecuteTenantJson(DbMaster, "academics.fn_assignment_delete", tenantId,
            new { assignment_id = assignmentId });
}
