using Newtonsoft.Json;

namespace EduNestIO.Common.Logging;

/// <summary>
/// Lightweight structured logger. This is an original substitute for the reference
/// project's proprietary Common.Log.LogWriter (a binary DLL that cannot be copied),
/// preserving the same call shape: LogWriter.WriteLog(new LogDTO {...}, payload).
///
/// Output is written to the console and to a daily rolling file under /logs. It is
/// deliberately simple and dependency-free; it can be swapped for NLog/Serilog later
/// without changing any call site. Sensitive values (passwords, tokens) must never be
/// passed as the payload object.
/// </summary>
public static class LogWriter
{
    private static readonly object Gate = new();
    private static string _logDirectory = Path.Combine(AppContext.BaseDirectory, "logs");

    /// <summary>Minimum level actually emitted. Detail is verbose; raise in production.</summary>
    public static LoggingLevel MinimumLevel { get; set; } = LoggingLevel.Detail;

    public static void Configure(string logDirectory, LoggingLevel minimumLevel)
    {
        _logDirectory = logDirectory;
        MinimumLevel = minimumLevel;
    }

    public static void WriteLog(LogDTO log)
    {
        WriteInternal(log, payloadJson: null);
    }

    public static void WriteLog<T>(LogDTO log, T payload)
    {
        string? json = null;
        try
        {
            json = payload is null ? null : JsonConvert.SerializeObject(payload);
        }
        catch
        {
            json = "<unserializable payload>";
        }

        WriteInternal(log, json);
    }

    private static void WriteInternal(LogDTO log, string? payloadJson)
    {
        if (log.LogStringLevel < MinimumLevel)
        {
            return;
        }

        var line =
            $"{DateTime.UtcNow:yyyy-MM-ddTHH:mm:ss.fffZ} [{log.LogStringLevel}] " +
            $"{log.ClassName}.{log.FunctionName} {log.AdditionalInfo} {log.Message}" +
            (string.IsNullOrEmpty(log.CorrelationId) ? "" : $" cid={log.CorrelationId}") +
            (string.IsNullOrEmpty(payloadJson) ? "" : $" payload={payloadJson}") +
            (string.IsNullOrEmpty(log.ExceptionString) ? "" : $" ex={log.ExceptionString}") +
            (string.IsNullOrEmpty(log.StackTrace) ? "" : $" stack={log.StackTrace}");

        try
        {
            Console.WriteLine(line);
            lock (Gate)
            {
                Directory.CreateDirectory(_logDirectory);
                var file = Path.Combine(_logDirectory, $"edunestio-{DateTime.UtcNow:yyyyMMdd}.log");
                File.AppendAllText(file, line + Environment.NewLine);
            }
        }
        catch
        {
            // Logging must never throw into business flow.
        }
    }
}
