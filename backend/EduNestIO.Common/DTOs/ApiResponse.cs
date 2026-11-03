namespace EduNestIO.Common.DTOs;

/// <summary>
/// Consistent API response envelope used by all controllers. Keeps the reference
/// project's style of returning a result code + description alongside data.
/// </summary>
public class ApiResponse
{
    public bool IsSuccess { get; set; }
    public int ResultCode { get; set; }
    public string? ResultCodeDescription { get; set; }
    public string? CorrelationId { get; set; }
    public object? Data { get; set; }

    public static ApiResponse Ok(object? data = null, string? correlationId = null) => new()
    {
        IsSuccess = true,
        ResultCode = (int)ResultCodes.SUCCESS,
        ResultCodeDescription = ResultCodes.SUCCESS.GetDisplayName(),
        CorrelationId = correlationId,
        Data = data
    };

    public static ApiResponse Fail(ResultCodes code, string? message = null, string? correlationId = null) => new()
    {
        IsSuccess = false,
        ResultCode = (int)code,
        ResultCodeDescription = message ?? code.GetDisplayName(),
        CorrelationId = correlationId
    };
}

/// <summary>
/// Shape of the JSON envelope returned by every stored function. The DA layer
/// deserializes the function's jsonb result into this type.
/// </summary>
public class DbResult
{
    public int result_code { get; set; }
    public string? message { get; set; }
    public Newtonsoft.Json.Linq.JToken? data { get; set; }
}

/// <summary>Standard paged payload mirrored from the DB (snake_case from jsonb).</summary>
public class PagedData<T>
{
    public List<T> items { get; set; } = new();
    public int page { get; set; }
    public int page_size { get; set; }
    public long total_count { get; set; }
}
