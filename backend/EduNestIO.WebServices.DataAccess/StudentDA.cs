using EduNestIO.Common.Data;
using EduNestIO.Common.DTOs;

namespace EduNestIO.WebServices.DataAccess;

/// <summary>
/// Data access for the Student module. Each method invokes a PostgreSQL stored
/// function and returns the deserialized envelope. No SQL is built from user input
/// (all values travel as a jsonb parameter), which prevents SQL injection.
/// </summary>
public class StudentDA : DBBase
{
    public StudentDA(string connectionString = "") : base(connectionString) { }

    public DbResult Save(int tenantId, object studentPayload) =>
        DAHelper.ExecuteTenantJson(DbMaster, "academics.fn_student_save", tenantId, studentPayload);

    public DbResult Get(int tenantId, long studentId) =>
        DAHelper.ExecuteTenantJson(DbMaster, "academics.fn_student_get", tenantId, new { student_id = studentId });

    public DbResult List(int tenantId, object queryPayload) =>
        DAHelper.ExecuteTenantJson(DbMaster, "academics.fn_student_list", tenantId, queryPayload);

    public DbResult Delete(int tenantId, long studentId, long actorUserId) =>
        DAHelper.ExecuteTenantJson(DbMaster, "academics.fn_student_delete", tenantId,
            new { student_id = studentId, ActorUserId = actorUserId });

    public DbResult SetStatus(int tenantId, object payload) =>
        DAHelper.ExecuteTenantJson(DbMaster, "academics.fn_student_set_status", tenantId, payload);

    public DbResult Summary(int tenantId) =>
        DAHelper.ExecuteTenantJson(DbMaster, "academics.fn_student_summary", tenantId, new { });

    public DbResult Enrollments(int tenantId, long studentId) =>
        DAHelper.ExecuteTenantJson(DbMaster, "academics.fn_student_enrollments", tenantId,
            new { student_id = studentId });

    public DbResult Promote(int tenantId, object payload) =>
        DAHelper.ExecuteTenantJson(DbMaster, "academics.fn_student_promote", tenantId, payload);

    public DbResult Graduate(int tenantId, object payload) =>
        DAHelper.ExecuteTenantJson(DbMaster, "academics.fn_student_graduate", tenantId, payload);

    public DbResult Withdraw(int tenantId, object payload) =>
        DAHelper.ExecuteTenantJson(DbMaster, "academics.fn_student_withdraw", tenantId, payload);
}
