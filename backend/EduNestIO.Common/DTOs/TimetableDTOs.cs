namespace EduNestIO.Common.DTOs;

/// <summary>One weekly timetable slot (create/update).</summary>
public class TimetableSlotVO
{
    public long? SlotId { get; set; }
    public long ClassId { get; set; }
    public long? SectionId { get; set; }
    public int DayOfWeek { get; set; }   // 1=Mon .. 6=Sat
    public int PeriodNo { get; set; }
    public string? StartTime { get; set; } // "HH:mm"
    public string? EndTime { get; set; }
    public long? SubjectId { get; set; }
    public long? TeacherId { get; set; }
    public string? Room { get; set; }
}
