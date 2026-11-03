namespace EduNestIO.Common.DTOs;

/// <summary>One student's status within a bulk attendance submission.</summary>
public class AttendanceEntryVO
{
    public long StudentId { get; set; }
    public string Status { get; set; } = "Present"; // Present|Absent|Late|Leave
    public string? Remark { get; set; }
}

/// <summary>Bulk mark request for a class on a date (optionally a section / subject).</summary>
public class AttendanceMarkVO
{
    public long ClassId { get; set; }
    public long? SectionId { get; set; }
    public long? SubjectId { get; set; }
    public DateTime AttendDate { get; set; }
    public List<AttendanceEntryVO> Entries { get; set; } = new();
}
