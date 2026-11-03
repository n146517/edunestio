namespace EduNestIO.Common.Logging;

/// <summary>
/// Logging levels mirroring the reference project's Common.Log semantics.
/// </summary>
public enum LoggingLevel
{
    Detail = 0,
    Info = 1,
    Warning = 2,
    Exceptional = 3
}

/// <summary>
/// Structured log payload used across all layers. Mirrors the reference project's
/// LogDTO so Controller/BL/DA logging calls read identically.
/// </summary>
public sealed class LogDTO
{
    public string? FunctionName { get; set; }
    public string? ClassName { get; set; }
    public string? Message { get; set; }
    public string? AdditionalInfo { get; set; }
    public LoggingLevel LogStringLevel { get; set; } = LoggingLevel.Detail;
    public string? ExceptionString { get; set; }
    public string? StackTrace { get; set; }

    /// <summary>Correlation id so a request can be traced across layers.</summary>
    public string? CorrelationId { get; set; }
}
