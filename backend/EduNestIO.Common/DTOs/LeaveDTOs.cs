namespace EduNestIO.Common.DTOs;

/// <summary>A student's (or guardian's) leave application.</summary>
public class LeaveApplyVO
{
    /// <summary>Target student. For a self-service login this is ignored and the
    /// server uses the caller's linked student id instead.</summary>
    public long? StudentId { get; set; }
    public DateTime FromDate { get; set; }
    public DateTime ToDate { get; set; }
    public string? LeaveType { get; set; } // Sick | Casual | Other
    public string Reason { get; set; } = string.Empty;
}

/// <summary>Approve / reject decision on a pending leave request.</summary>
public class LeaveDecisionVO
{
    public string Decision { get; set; } = string.Empty; // Approved | Rejected
    public string? Note { get; set; }
}
