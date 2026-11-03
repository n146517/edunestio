namespace EduNestIO.Common.DTOs;

/// <summary>Enquiry create/update VO (no tenant id; server-derived).</summary>
public class EnquiryVO
{
    public long? EnquiryId { get; set; }
    public string ApplicantName { get; set; } = string.Empty;
    public string? GuardianName { get; set; }
    public string? Phone { get; set; }
    public string? Email { get; set; }
    public string? Source { get; set; }
    public long? DesiredClassId { get; set; }
    public string? Stage { get; set; }
    public string? Notes { get; set; }
    public DateTime? NextFollowupAt { get; set; }
}

public class EnquiryQueryVO
{
    public string? Search { get; set; }
    public string? Stage { get; set; }
    public int Page { get; set; } = 1;
    public int PageSize { get; set; } = 20;
}

public class FollowupVO
{
    public long EnquiryId { get; set; }
    public string Note { get; set; } = string.Empty;
    public string? Outcome { get; set; }
    public string? Stage { get; set; }
}

public class ConvertEnquiryVO
{
    public long EnquiryId { get; set; }
    public string? FirstName { get; set; }
    public string? LastName { get; set; }
}
