namespace EduNestIO.Common.DTOs;

/// <summary>Academic year create/update VO. No tenant id (server-derived).</summary>
public class AcademicYearVO
{
    public long? AcademicYearId { get; set; }
    public string Name { get; set; } = string.Empty;
    public DateTime? StartDate { get; set; }
    public DateTime? EndDate { get; set; }
    public bool IsCurrent { get; set; }
}

public class ClassVO
{
    public long? ClassId { get; set; }
    public string Name { get; set; } = string.Empty;
    public int Ordinal { get; set; }
}

public class SectionVO
{
    public long? SectionId { get; set; }
    public long ClassId { get; set; }
    public string Name { get; set; } = string.Empty;
}

public class SubjectVO
{
    public long? SubjectId { get; set; }
    public string Name { get; set; } = string.Empty;
    public string Code { get; set; } = string.Empty;
    public bool IsActive { get; set; } = true;
}
