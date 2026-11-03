namespace EduNestIO.Common.DTOs;

/// <summary>Writable school settings (admin).</summary>
public class SettingsVO
{
    /// <summary>'Daily' = one attendance per student per day; 'Subject' = per subject.</summary>
    public string? AttendanceMode { get; set; }
}
