namespace EduNestIO.Common.DTOs;

/// <summary>Create/update an exam. An exam can span multiple classes.</summary>
public class ExamVO
{
    public long? ExamId { get; set; }
    public string Name { get; set; } = string.Empty;
    public string? ExamType { get; set; }
    public long? AcademicYearId { get; set; }
    public DateTime? StartDate { get; set; }
    public DateTime? EndDate { get; set; }
    public string? Description { get; set; }
    public List<long> ClassIds { get; set; } = new();
}

/// <summary>Filters for the exams list.</summary>
public class ExamQueryVO
{
    public string? Search { get; set; }
    public long? ClassId { get; set; }
    public long? AcademicYearId { get; set; }
    public string? Status { get; set; }
    public string? ExamType { get; set; }
}

/// <summary>Attach a subject to an exam with its max/pass marks (legacy single-add).</summary>
public class ExamSubjectVO
{
    public long ExamId { get; set; }
    public long SubjectId { get; set; }
    public decimal MaxMarks { get; set; } = 100;
    public decimal PassMarks { get; set; } = 33;
}

/// <summary>One subject row in a class's exam-subject configuration.</summary>
public class ExamSubjectRowVO
{
    public long? ExamSubjectId { get; set; }
    public long SubjectId { get; set; }
    public decimal MaxMarks { get; set; } = 100;
    public decimal PassMarks { get; set; } = 33;
    public string SubjectType { get; set; } = "Theory";
}

/// <summary>Save the full subject set for one class of an exam (reconciling delete).</summary>
public class ExamClassSubjectsVO
{
    public long ExamId { get; set; }
    public long ClassId { get; set; }
    public List<ExamSubjectRowVO> Subjects { get; set; } = new();
}

/// <summary>One schedule row for an exam subject.</summary>
public class ExamScheduleRowVO
{
    public long ExamSubjectId { get; set; }
    public DateTime? ExamDate { get; set; }
    public string? StartTime { get; set; }
    public string? EndTime { get; set; }
    public string? Room { get; set; }
}

/// <summary>Bulk save of an exam's subject schedule.</summary>
public class ExamScheduleSaveVO
{
    public long ExamId { get; set; }
    public List<ExamScheduleRowVO> Items { get; set; } = new();
}

/// <summary>One student's mark within a bulk marks submission.</summary>
public class ExamMarkEntryVO
{
    public long StudentId { get; set; }
    public decimal? Marks { get; set; }
    public bool IsAbsent { get; set; }
}

/// <summary>Bulk save of marks for an exam subject.</summary>
public class ExamMarksSaveVO
{
    public long ExamSubjectId { get; set; }
    public List<ExamMarkEntryVO> Entries { get; set; } = new();
}

/// <summary>Publish or unpublish an exam's results. Force overrides the missing-marks guard.</summary>
public class ExamPublishVO
{
    public long ExamId { get; set; }
    public bool Publish { get; set; } = true;
    public bool Force { get; set; }
}
