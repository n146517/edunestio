namespace EduNestIO.Common.DTOs;

/// <summary>Login request (VO) sent by the client.</summary>
public class LoginVO
{
    public string Username { get; set; } = string.Empty;
    public string Password { get; set; } = string.Empty;
}

/// <summary>Login result returned to the client. Token is an opaque session token.</summary>
public class LoginResultDTO
{
    public string Token { get; set; } = string.Empty;
    public DateTime ExpiresAtUtc { get; set; }
    public long UserId { get; set; }
    public int TenantId { get; set; }
    public string Username { get; set; } = string.Empty;
    public string? Email { get; set; }
    public string? FullName { get; set; }
    public string? TenantName { get; set; }
    public long? StudentId { get; set; }
    public List<string> Roles { get; set; } = new();
    public List<string> Permissions { get; set; } = new();
}
