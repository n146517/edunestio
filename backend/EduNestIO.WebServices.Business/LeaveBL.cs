using EduNestIO.Common.DTOs;
using EduNestIO.WebServices.DataAccess;
using static EduNestIO.WebServices.Business.DBManagerDA;

namespace EduNestIO.WebServices.Business;

/// <summary>Business logic for the Leave module.</summary>
public class LeaveBL
{
    private static LeaveDA Da() => (LeaveDA)GetDBObject(DAType.Leave)!;

    /// <summary>Apply for leave. effectiveStudentId is the resolved student
    /// (caller's own for self-service, or the supplied one for staff).</summary>
    public DbResult Apply(int tenantId, long actorUserId, long effectiveStudentId, LeaveApplyVO vo)
    {
        LeaveDA? da = null;
        try
        {
            da = Da();
            var payload = new
            {
                student_id = effectiveStudentId,
                from_date = vo.FromDate.ToString("yyyy-MM-dd"),
                to_date = vo.ToDate.ToString("yyyy-MM-dd"),
                leave_type = vo.LeaveType,
                reason = vo.Reason,
                actor_user_id = actorUserId
            };
            return da.Apply(tenantId, payload);
        }
        finally { ReleaseDBObject(da); }
    }

    public DbResult Mine(int tenantId, long studentId)
    {
        LeaveDA? da = null;
        try { da = Da(); return da.Mine(tenantId, studentId); }
        finally { ReleaseDBObject(da); }
    }

    public DbResult List(int tenantId, string? status, long? classId, string? search)
    {
        LeaveDA? da = null;
        try { da = Da(); return da.List(tenantId, status, classId, search); }
        finally { ReleaseDBObject(da); }
    }

    /// <summary>Cancel a leave. studentId (when provided) restricts to the caller's own.</summary>
    public DbResult Cancel(int tenantId, long leaveId, long? studentId)
    {
        LeaveDA? da = null;
        try { da = Da(); return da.Cancel(tenantId, leaveId, studentId); }
        finally { ReleaseDBObject(da); }
    }

    public DbResult Decide(int tenantId, long actorUserId, long leaveId, LeaveDecisionVO vo)
    {
        LeaveDA? da = null;
        try
        {
            da = Da();
            var payload = new { leave_id = leaveId, decision = vo.Decision, note = vo.Note, actor_user_id = actorUserId };
            return da.Decide(tenantId, payload);
        }
        finally { ReleaseDBObject(da); }
    }
}
