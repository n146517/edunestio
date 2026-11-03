namespace EduNestIO.Common;

/// <summary>
/// Canonical result codes returned in API responses, mirroring the reference
/// project's ResultCodes enum style. Stored functions return a matching
/// numeric code in their JSON envelope.
/// </summary>
public enum ResultCodes
{
    SUCCESS = 0,
    DB_ERROR = 1,
    DB_RESPONSE_NULL = 2,
    VALIDATION_ERROR = 3,
    NOT_FOUND = 4,
    UNAUTHORIZED = 5,
    FORBIDDEN = 6,
    DUPLICATE = 7,
    TENANT_MISMATCH = 8,
    INTERNAL_SERVER_ERROR = 99
}

public static class ResultCodeExtensions
{
    public static string GetDisplayName(this ResultCodes code) => code switch
    {
        ResultCodes.SUCCESS => "Success",
        ResultCodes.DB_ERROR => "Database error",
        ResultCodes.DB_RESPONSE_NULL => "No response from database",
        ResultCodes.VALIDATION_ERROR => "Validation failed",
        ResultCodes.NOT_FOUND => "Resource not found",
        ResultCodes.UNAUTHORIZED => "Unauthorized",
        ResultCodes.FORBIDDEN => "Forbidden",
        ResultCodes.DUPLICATE => "Duplicate record",
        ResultCodes.TENANT_MISMATCH => "Tenant access violation",
        _ => "An unexpected error occurred"
    };
}
