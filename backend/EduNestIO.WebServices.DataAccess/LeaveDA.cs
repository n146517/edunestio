using EduNestIO.Common.Data;
using EduNestIO.Common.DTOs;

namespace EduNestIO.WebServices.DataAccess;

/// <summary>Data access for the Leave module. Thin one-liners over stored functions.</summary>
public class LeaveDA : DBBase
{
    public LeaveDA(string connectionString = "") : base(connectionString) { }

    public DbResult Apply(int tenantId, object payload) =>
        DAHelper.ExecuteTenantJson(DbMaster, "academics.fn_leave_apply", tenantId, payload);

    public DbResult Mine(int tenantId, long studentId) =>
        DAHelper.ExecuteTenantJson(DbMaster, "academics.fn_leave_mine", tenantId,
            new { student_id = studentId });

    public DbResult List(int tenantId, string? status, long? classId, string? search) =>
        DAHelper.ExecuteTenantJson(DbMaster, "academics.fn_leave_list", tenantId,
            new { status, class_id = classId, search });

    public DbResult Cancel(int tenantId, long leaveId, long? studentId) =>
        DAHelper.ExecuteTenantJson(DbMaster, "academics.fn_leave_cancel", tenantId,
            new { leave_id = leaveId, student_id = studentId });

    public DbResult Decide(int tenantId, object payload) =>
        DAHelper.ExecuteTenantJson(DbMaster, "academics.fn_leave_decide", tenantId, payload);
}
