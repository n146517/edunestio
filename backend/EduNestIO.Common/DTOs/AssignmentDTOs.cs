namespace EduNestIO.Common.DTOs;

/// <summary>Create/update an assignment (teacher/staff).</summary>
public class AssignmentVO
{
    public long? AssignmentId { get; set; }
    public long ClassId { get; set; }
    public long? SectionId { get; set; }
    public long? SubjectId { get; set; }
    public long? TeacherId { get; set; }
    public string Title { get; set; } = string.Empty;
    public string? Description { get; set; }
    public string? DueDate { get; set; }   // yyyy-MM-dd
    public decimal? MaxMarks { get; set; }
}

/// <summary>A student submitting their work.</summary>
public class AssignmentSubmitVO
{
    public long AssignmentId { get; set; }
    public string? Content { get; set; }
}

/// <summary>A teacher grading a submission.</summary>
public class AssignmentGradeVO
{
    public long SubmissionId { get; set; }
    public decimal? Marks { get; set; }
    public string? Feedback { get; set; }
}
